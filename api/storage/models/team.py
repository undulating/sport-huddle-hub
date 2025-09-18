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
    meta_data = Column(JSON)
    
    # Relationships
    home_games = relationship("Game", foreign_keys="Game.home_team_id", back_populates="home_team")
    away_games = relationship("Game", foreign_keys="Game.away_team_id", back_populates="away_team")
    injuries = relationship("Injury", back_populates="team")
