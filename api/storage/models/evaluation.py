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
