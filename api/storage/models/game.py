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
