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
