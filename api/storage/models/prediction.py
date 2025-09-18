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
    meta_data = Column(JSON)
    
    # Relationships
    game = relationship("Game", back_populates="predictions")
    model_version = relationship("ModelVersion", back_populates="predictions")
    model_run = relationship("ModelRun", back_populates="predictions")
    evaluation = relationship("Evaluation", back_populates="prediction", uselist=False)
