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
    meta_data = Column(JSON)
    checksum = Column(String(64), index=True)
    
    # Relationships
    game = relationship("Game", back_populates="odds_records")
