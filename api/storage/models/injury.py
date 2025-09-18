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
