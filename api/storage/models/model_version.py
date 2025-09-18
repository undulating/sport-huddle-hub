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
    meta_data = Column(JSON)
    
    # Relationships
    runs = relationship("ModelRun", back_populates="model_version")
    predictions = relationship("Prediction", back_populates="model_version")
