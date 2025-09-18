#!/bin/bash
# phase2-setup.sh
# Phase 2: Database Schema & Models Implementation

set -e

echo "==================================="
echo "Phase 2: Database Schema & Models"
echo "==================================="

# Step 1.2: Create Database Connection Layer
echo "Creating database connection layer..."

cat > api/storage/__init__.py << 'EOF'
"""Database storage module."""
EOF

cat > api/storage/db.py << 'EOF'
"""Database connection and session management."""
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker, Session
from sqlalchemy.pool import NullPool, QueuePool
from contextlib import contextmanager
from typing import Generator

from api.config import settings
from api.logging import get_logger

logger = get_logger(__name__)

# Create engine with connection pooling
engine = create_engine(
    settings.DATABASE_URL,
    poolclass=QueuePool,
    pool_size=settings.DATABASE_POOL_SIZE if hasattr(settings, 'DATABASE_POOL_SIZE') else 10,
    max_overflow=settings.DATABASE_MAX_OVERFLOW if hasattr(settings, 'DATABASE_MAX_OVERFLOW') else 20,
    pool_pre_ping=True,  # Verify connections before using
    echo=settings.ENVIRONMENT == "development",  # Log SQL in development
)

# Create session factory
SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine,
    class_=Session,
    expire_on_commit=False,
)


def get_db() -> Generator[Session, None, None]:
    """
    Dependency to get database session.
    Ensures proper cleanup after request.
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


@contextmanager
def get_db_context():
    """Context manager for database sessions."""
    db = SessionLocal()
    try:
        yield db
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def init_db() -> None:
    """Initialize database - create tables if they don't exist."""
    from api.storage.base import Base
    
    logger.info("Initializing database...")
    Base.metadata.create_all(bind=engine)
    logger.info("Database initialized successfully")


def check_db_connection() -> bool:
    """Check if database is accessible."""
    try:
        with engine.connect() as conn:
            conn.execute("SELECT 1")
        return True
    except Exception as e:
        logger.error(f"Database connection failed: {e}")
        return False
EOF

cat > api/storage/base.py << 'EOF'
"""Base model for all database models."""
from datetime import datetime
from typing import Any

from sqlalchemy import Column, DateTime, Integer
from sqlalchemy.ext.declarative import as_declarative, declared_attr


@as_declarative()
class Base:
    """Base class for all database models."""
    
    id: Any
    __name__: str
    
    # Generate table name automatically
    @declared_attr
    def __tablename__(cls) -> str:
        """Generate table name from class name."""
        # Convert CamelCase to snake_case
        import re
        name = re.sub('(.)([A-Z][a-z]+)', r'\1_\2', cls.__name__)
        return re.sub('([a-z0-9])([A-Z])', r'\1_\2', name).lower()
    
    # Common timestamp columns
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
EOF

# Step 2.1: Create Core Database Models
echo "Creating core database models..."

cat > api/storage/models/__init__.py << 'EOF'
"""Database models."""
from api.storage.models.team import Team
from api.storage.models.game import Game
from api.storage.models.odds import Odds
from api.storage.models.injury import Injury
from api.storage.models.weather import Weather

__all__ = ["Team", "Game", "Odds", "Injury", "Weather"]
EOF

cat > api/storage/models/team.py << 'EOF'
"""Team model."""
from sqlalchemy import Column, String, Integer, Float, JSON
from sqlalchemy.orm import relationship

from api.storage.base import Base


class Team(Base):
    """NFL Team model."""
    
    __tablename__ = "teams"
    
    id = Column(Integer, primary_key=True, index=True)
    external_id = Column(String(50), unique=True, nullable=False, index=True)
    name = Column(String(100), nullable=False)
    city = Column(String(50), nullable=False)
    abbreviation = Column(String(5), nullable=False, unique=True, index=True)
    conference = Column(String(3), nullable=False)  # AFC or NFC
    division = Column(String(20), nullable=False)
    
    # Team colors for UI
    primary_color = Column(String(7))  # Hex color
    secondary_color = Column(String(7))  # Hex color
    
    # Season stats (updated regularly)
    wins = Column(Integer, default=0)
    losses = Column(Integer, default=0)
    ties = Column(Integer, default=0)
    
    # Rating metrics (calculated)
    elo_rating = Column(Float, default=1500.0)
    offensive_rating = Column(Float)
    defensive_rating = Column(Float)
    
    # Additional metadata
    stadium_name = Column(String(100))
    stadium_capacity = Column(Integer)
    head_coach = Column(String(100))
    metadata = Column(JSON)
    
    # Relationships
    home_games = relationship("Game", foreign_keys="Game.home_team_id", back_populates="home_team")
    away_games = relationship("Game", foreign_keys="Game.away_team_id", back_populates="away_team")
    injuries = relationship("Injury", back_populates="team")
EOF

cat > api/storage/models/game.py << 'EOF'
"""Game model."""
from sqlalchemy import Column, String, Integer, Float, DateTime, Boolean, ForeignKey, Index, CheckConstraint
from sqlalchemy.orm import relationship

from api.storage.base import Base


class Game(Base):
    """NFL Game model."""
    
    __tablename__ = "games"
    __table_args__ = (
        Index('idx_game_date', 'game_date'),
        Index('idx_season_week', 'season', 'week'),
        Index('idx_teams', 'home_team_id', 'away_team_id'),
        CheckConstraint('home_score >= 0', name='check_home_score_positive'),
        CheckConstraint('away_score >= 0', name='check_away_score_positive'),
    )
    
    id = Column(Integer, primary_key=True, index=True)
    external_id = Column(String(50), unique=True, nullable=False, index=True)
    
    # Season info
    season = Column(Integer, nullable=False)
    season_type = Column(String(20), nullable=False)  # PRE, REG, POST
    week = Column(Integer, nullable=False)
    
    # Teams
    home_team_id = Column(Integer, ForeignKey("teams.id"), nullable=False)
    away_team_id = Column(Integer, ForeignKey("teams.id"), nullable=False)
    
    # Game timing
    game_date = Column(DateTime, nullable=False)
    kickoff_time = Column(DateTime, nullable=False)
    
    # Game status
    status = Column(String(20), default="SCHEDULED")  # SCHEDULED, IN_PROGRESS, FINAL, POSTPONED, CANCELLED
    quarter = Column(Integer)
    time_remaining = Column(String(10))
    
    # Scores
    home_score = Column(Integer)
    away_score = Column(Integer)
    home_score_q1 = Column(Integer)
    home_score_q2 = Column(Integer)
    home_score_q3 = Column(Integer)
    home_score_q4 = Column(Integer)
    home_score_ot = Column(Integer)
    away_score_q1 = Column(Integer)
    away_score_q2 = Column(Integer)
    away_score_q3 = Column(Integer)
    away_score_q4 = Column(Integer)
    away_score_ot = Column(Integer)
    
    # Location
    stadium = Column(String(100))
    dome = Column(Boolean, default=False)
    surface = Column(String(20))  # grass, turf
    
    # Game conditions
    temperature = Column(Float)
    wind_speed = Column(Float)
    weather_condition = Column(String(50))
    
    # Betting info
    home_spread = Column(Float)
    total_over_under = Column(Float)
    
    # Checksums for deduplication
    checksum = Column(String(64), index=True)
    
    # Relationships
    home_team = relationship("Team", foreign_keys=[home_team_id], back_populates="home_games")
    away_team = relationship("Team", foreign_keys=[away_team_id], back_populates="away_games")
    odds_records = relationship("Odds", back_populates="game", cascade="all, delete-orphan")
    weather_records = relationship("Weather", back_populates="game", cascade="all, delete-orphan")
    predictions = relationship("Prediction", back_populates="game", cascade="all, delete-orphan")
EOF

cat > api/storage/models/odds.py << 'EOF'
"""Odds model."""
from sqlalchemy import Column, String, Integer, Float, DateTime, ForeignKey, Index, JSON
from sqlalchemy.orm import relationship

from api.storage.base import Base


class Odds(Base):
    """Betting odds for games."""
    
    __tablename__ = "odds"
    __table_args__ = (
        Index('idx_odds_game_provider', 'game_id', 'provider'),
        Index('idx_odds_timestamp', 'timestamp'),
    )
    
    id = Column(Integer, primary_key=True, index=True)
    game_id = Column(Integer, ForeignKey("games.id"), nullable=False)
    
    # Provider info
    provider = Column(String(50), nullable=False)  # draftkings, fanduel, etc.
    timestamp = Column(DateTime, nullable=False)
    
    # Spread betting
    home_spread = Column(Float, nullable=False)
    home_spread_odds = Column(Integer, default=-110)
    away_spread = Column(Float, nullable=False)
    away_spread_odds = Column(Integer, default=-110)
    
    # Moneyline
    home_moneyline = Column(Integer)
    away_moneyline = Column(Integer)
    
    # Totals (Over/Under)
    total = Column(Float)
    over_odds = Column(Integer, default=-110)
    under_odds = Column(Integer, default=-110)
    
    # Movement tracking
    home_spread_open = Column(Float)
    total_open = Column(Float)
    
    # Market consensus
    home_spread_consensus = Column(Float)
    total_consensus = Column(Float)
    
    # Betting percentages
    home_spread_percentage = Column(Float)  # % of bets on home team
    over_percentage = Column(Float)  # % of bets on over
    
    # Additional data
    metadata = Column(JSON)
    checksum = Column(String(64), index=True)
    
    # Relationships
    game = relationship("Game", back_populates="odds_records")
EOF

cat > api/storage/models/injury.py << 'EOF'
"""Injury model."""
from sqlalchemy import Column, String, Integer, DateTime, ForeignKey, Index
from sqlalchemy.orm import relationship

from api.storage.base import Base


class Injury(Base):
    """Player injury reports."""
    
    __tablename__ = "injuries"
    __table_args__ = (
        Index('idx_injury_team_week', 'team_id', 'season', 'week'),
        Index('idx_injury_status', 'injury_status'),
    )
    
    id = Column(Integer, primary_key=True, index=True)
    team_id = Column(Integer, ForeignKey("teams.id"), nullable=False)
    
    # Player info
    player_name = Column(String(100), nullable=False)
    player_position = Column(String(10), nullable=False)
    player_number = Column(Integer)
    
    # Injury details
    injury_status = Column(String(20), nullable=False)  # OUT, DOUBTFUL, QUESTIONABLE, PROBABLE
    injury_type = Column(String(50))  # knee, ankle, etc.
    injury_description = Column(String(255))
    
    # Timing
    season = Column(Integer, nullable=False)
    week = Column(Integer, nullable=False)
    report_date = Column(DateTime, nullable=False)
    
    # Practice participation
    practice_status_wed = Column(String(20))  # DNP, LIMITED, FULL
    practice_status_thu = Column(String(20))
    practice_status_fri = Column(String(20))
    
    # Checksum for deduplication
    checksum = Column(String(64), index=True)
    
    # Relationships
    team = relationship("Team", back_populates="injuries")
EOF

cat > api/storage/models/weather.py << 'EOF'
"""Weather model."""
from sqlalchemy import Column, String, Integer, Float, DateTime, Boolean, ForeignKey, Index, JSON
from sqlalchemy.orm import relationship

from api.storage.base import Base


class Weather(Base):
    """Weather conditions for outdoor games."""
    
    __tablename__ = "weather"
    __table_args__ = (
        Index('idx_weather_game', 'game_id'),
        Index('idx_weather_forecast_time', 'forecast_time'),
    )
    
    id = Column(Integer, primary_key=True, index=True)
    game_id = Column(Integer, ForeignKey("games.id"), nullable=False)
    
    # Forecast timing
    forecast_time = Column(DateTime, nullable=False)
    hours_before_game = Column(Float)
    
    # Temperature
    temperature = Column(Float)  # Fahrenheit
    feels_like = Column(Float)
    
    # Wind
    wind_speed = Column(Float)  # mph
    wind_direction = Column(String(10))  # N, NE, E, etc.
    wind_gust = Column(Float)
    
    # Precipitation
    precipitation_probability = Column(Float)  # 0-100%
    precipitation_type = Column(String(20))  # rain, snow, mix
    precipitation_intensity = Column(Float)  # inches per hour
    
    # Conditions
    humidity = Column(Float)  # 0-100%
    visibility = Column(Float)  # miles
    pressure = Column(Float)  # inches Hg
    cloud_cover = Column(Float)  # 0-100%
    
    # General conditions
    condition = Column(String(50))  # clear, cloudy, rain, snow, etc.
    indoor = Column(Boolean, default=False)
    
    # Provider
    provider = Column(String(50))
    
    # Additional data
    metadata = Column(JSON)
    checksum = Column(String(64), index=True)
    
    # Relationships
    game = relationship("Game", back_populates="weather_records")
EOF

echo "✅ Core models created"

# Step 2.2: Create ML/Prediction Models
echo "Creating ML and prediction models..."

cat > api/storage/models/model_version.py << 'EOF'
"""Model version registry."""
from sqlalchemy import Column, String, Integer, Float, Boolean, JSON, DateTime
from sqlalchemy.orm import relationship

from api.storage.base import Base


class ModelVersion(Base):
    """ML model versions."""
    
    __tablename__ = "model_versions"
    
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(50), nullable=False)  # elo_epa, gradient_boost, etc.
    version = Column(String(20), nullable=False)  # semver: 1.0.0
    
    # Model configuration
    model_type = Column(String(50), nullable=False)  # classification, regression
    features_used = Column(JSON)  # List of feature names
    hyperparameters = Column(JSON)  # Model hyperparameters
    
    # Performance metrics
    train_accuracy = Column(Float)
    validation_accuracy = Column(Float)
    train_log_loss = Column(Float)
    validation_log_loss = Column(Float)
    
    # Status
    is_active = Column(Boolean, default=True)
    is_default = Column(Boolean, default=False)
    
    # Training info
    trained_at = Column(DateTime)
    training_data_start = Column(DateTime)
    training_data_end = Column(DateTime)
    training_games_count = Column(Integer)
    
    # Additional metadata
    description = Column(String(500))
    metadata = Column(JSON)
    
    # Relationships
    runs = relationship("ModelRun", back_populates="model_version")
    predictions = relationship("Prediction", back_populates="model_version")
EOF

cat > api/storage/models/model_run.py << 'EOF'
"""Model run tracking."""
from sqlalchemy import Column, String, Integer, Float, DateTime, Boolean, ForeignKey, Index, JSON
from sqlalchemy.orm import relationship

from api.storage.base import Base


class ModelRun(Base):
    """Track model training/prediction runs."""
    
    __tablename__ = "model_runs"
    __table_args__ = (
        Index('idx_run_model_season', 'model_version_id', 'season', 'week'),
        Index('idx_run_status', 'status'),
    )
    
    id = Column(Integer, primary_key=True, index=True)
    model_version_id = Column(Integer, ForeignKey("model_versions.id"), nullable=False)
    
    # Run info
    run_type = Column(String(20), nullable=False)  # TRAIN, PREDICT, BACKTEST
    season = Column(Integer, nullable=False)
    week = Column(Integer)
    
    # Status
    status = Column(String(20), default="PENDING")  # PENDING, RUNNING, SUCCESS, FAILED
    started_at = Column(DateTime)
    completed_at = Column(DateTime)
    duration_seconds = Column(Float)
    
    # Results
    games_processed = Column(Integer, default=0)
    predictions_made = Column(Integer, default=0)
    errors_count = Column(Integer, default=0)
    
    # Performance (for backtests)
    accuracy = Column(Float)
    log_loss = Column(Float)
    brier_score = Column(Float)
    
    # Logs
    log_messages = Column(JSON)  # Array of log entries
    error_message = Column(String(1000))
    
    # Configuration
    config = Column(JSON)  # Run configuration
    
    # Relationships
    model_version = relationship("ModelVersion", back_populates="runs")
    predictions = relationship("Prediction", back_populates="model_run")
    evaluations = relationship("Evaluation", back_populates="model_run")
EOF

cat > api/storage/models/prediction.py << 'EOF'
"""Prediction model."""
from sqlalchemy import Column, String, Integer, Float, DateTime, Boolean, ForeignKey, Index, JSON
from sqlalchemy.orm import relationship

from api.storage.base import Base


class Prediction(Base):
    """Model predictions for games."""
    
    __tablename__ = "predictions"
    __table_args__ = (
        Index('idx_pred_game_model', 'game_id', 'model_version_id'),
        Index('idx_pred_created', 'created_at'),
        Index('idx_pred_confidence', 'confidence'),
    )
    
    id = Column(Integer, primary_key=True, index=True)
    game_id = Column(Integer, ForeignKey("games.id"), nullable=False)
    model_version_id = Column(Integer, ForeignKey("model_versions.id"), nullable=False)
    model_run_id = Column(Integer, ForeignKey("model_runs.id"))
    
    # Predictions
    home_win_probability = Column(Float, nullable=False)  # 0.0 to 1.0
    away_win_probability = Column(Float, nullable=False)  # 0.0 to 1.0
    
    # Score predictions
    predicted_home_score = Column(Float)
    predicted_away_score = Column(Float)
    predicted_total_score = Column(Float)
    
    # Spread predictions
    predicted_spread = Column(Float)  # Negative = home favored
    spread_confidence = Column(Float)  # Confidence in spread prediction
    
    # Over/Under prediction
    predicted_over_probability = Column(Float)
    predicted_under_probability = Column(Float)
    
    # Model confidence
    confidence = Column(Float)  # Overall confidence 0.0 to 1.0
    prediction_std = Column(Float)  # Standard deviation of prediction
    
    # Features used (for interpretability)
    feature_importance = Column(JSON)
    
    # Timing
    predicted_at = Column(DateTime, nullable=False)
    hours_before_game = Column(Float)
    
    # Lock status
    is_locked = Column(Boolean, default=False)
    locked_at = Column(DateTime)
    
    # Additional data
    metadata = Column(JSON)
    
    # Relationships
    game = relationship("Game", back_populates="predictions")
    model_version = relationship("ModelVersion", back_populates="predictions")
    model_run = relationship("ModelRun", back_populates="predictions")
    evaluation = relationship("Evaluation", back_populates="prediction", uselist=False)
EOF

cat > api/storage/models/evaluation.py << 'EOF'
"""Evaluation model for prediction performance."""
from sqlalchemy import Column, Integer, Float, Boolean, ForeignKey, Index
from sqlalchemy.orm import relationship

from api.storage.base import Base


class Evaluation(Base):
    """Evaluation of predictions after game completion."""
    
    __tablename__ = "evaluations"
    __table_args__ = (
        Index('idx_eval_prediction', 'prediction_id'),
        Index('idx_eval_model_run', 'model_run_id'),
    )
    
    id = Column(Integer, primary_key=True, index=True)
    prediction_id = Column(Integer, ForeignKey("predictions.id"), nullable=False, unique=True)
    model_run_id = Column(Integer, ForeignKey("model_runs.id"))
    
    # Outcomes
    winner_correct = Column(Boolean)
    spread_correct = Column(Boolean)
    over_under_correct = Column(Boolean)
    
    # Errors
    score_error_home = Column(Float)  # Actual - Predicted
    score_error_away = Column(Float)
    total_score_error = Column(Float)
    spread_error = Column(Float)
    
    # Probability metrics
    log_loss = Column(Float)
    brier_score = Column(Float)
    
    # Betting performance
    spread_units_won = Column(Float)  # Units won/lost on spread bet
    moneyline_units_won = Column(Float)  # Units won/lost on moneyline
    over_under_units_won = Column(Float)  # Units won/lost on total
    
    # Relationships
    prediction = relationship("Prediction", back_populates="evaluation")
    model_run = relationship("ModelRun", back_populates="evaluations")
EOF

echo "✅ ML models created"

# Create Alembic configuration
echo "Setting up Alembic migrations..."

cat > alembic.ini << 'EOF'
# Alembic Configuration

[alembic]
script_location = api/storage/migrations
prepend_sys_path = .
version_path_separator = os
sqlalchemy.url = postgresql://nflpred:nflpred123@localhost:5432/nflpred

[post_write_hooks]

[loggers]
keys = root,sqlalchemy,alembic

[handlers]
keys = console

[formatters]
keys = generic

[logger_root]
level = WARN
handlers = console
qualname =

[logger_sqlalchemy]
level = WARN
handlers =
qualname = sqlalchemy.engine

[logger_alembic]
level = INFO
handlers =
qualname = alembic

[handler_console]
class = StreamHandler
args = (sys.stderr,)
level = NOTSET
formatter = generic

[formatter_generic]
format = %(levelname)-5.5s [%(name)s] %(message)s
datefmt = %H:%M:%S
EOF

mkdir -p api/storage/migrations

cat > api/storage/migrations/env.py << 'EOF'
"""Alembic environment configuration."""
from logging.config import fileConfig
from sqlalchemy import engine_from_config, pool
from alembic import context
import os
import sys
from pathlib import Path

# Add project root to path
sys.path.append(str(Path(__file__).parents[3]))

from api.config import settings
from api.storage.base import Base

# Import all models to ensure they're registered
from api.storage.models import *

config = context.config

# Set database URL from environment
config.set_main_option('sqlalchemy.url', settings.DATABASE_URL)

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode."""
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run migrations in 'online' mode."""
    connectable = engine_from_config(
        config.get_section(config.config_ini_section),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection, 
            target_metadata=target_metadata
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
EOF

cat > api/storage/migrations/script.py.mako << 'EOF'
"""${message}

Revision ID: ${up_revision}
Revises: ${down_revision | comma,n}
Create Date: ${create_date}

"""
from alembic import op
import sqlalchemy as sa
${imports if imports else ""}

# revision identifiers, used by Alembic.
revision = ${repr(up_revision)}
down_revision = ${repr(down_revision)}
branch_labels = ${repr(branch_labels)}
depends_on = ${repr(depends_on)}


def upgrade() -> None:
    ${upgrades if upgrades else "pass"}


def downgrade() -> None:
    ${downgrades if downgrades else "pass"}
EOF

echo "✅ Alembic configured"

echo ""
echo "==================================="
echo "Phase 2 Setup Complete!"
echo "==================================="
echo ""
echo "Next steps:"
echo "1. Update dependencies.py with database session"
echo "2. Create initial migration"
echo "3. Run migrations"
echo "4. Test database connection"
EOF