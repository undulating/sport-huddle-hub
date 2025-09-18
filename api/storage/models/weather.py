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
    meta_data = Column(JSON)
    checksum = Column(String(64), index=True)
    
    # Relationships
    game = relationship("Game", back_populates="weather_records")
