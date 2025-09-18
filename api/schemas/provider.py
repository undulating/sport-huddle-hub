"""Provider data transfer objects."""
from datetime import datetime
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field


class TeamDTO(BaseModel):
    """Team data from provider."""
    external_id: str
    name: str
    city: str
    abbreviation: str
    conference: str
    division: str
    wins: int = 0
    losses: int = 0
    ties: int = 0
    primary_color: Optional[str] = None
    secondary_color: Optional[str] = None
    stadium_name: Optional[str] = None
    head_coach: Optional[str] = None


class GameDTO(BaseModel):
    """Game data from provider."""
    external_id: str
    season: int
    season_type: str  # PRE, REG, POST
    week: int
    home_team_external_id: str
    away_team_external_id: str
    game_date: datetime
    kickoff_time: datetime
    status: str = "SCHEDULED"
    home_score: Optional[int] = None
    away_score: Optional[int] = None
    stadium: Optional[str] = None
    dome: bool = False
    surface: Optional[str] = None
    temperature: Optional[float] = None
    wind_speed: Optional[float] = None
    weather_condition: Optional[str] = None


class OddsDTO(BaseModel):
    """Odds data from provider."""
    game_external_id: str
    provider: str
    timestamp: datetime
    home_spread: float
    home_spread_odds: int = -110
    away_spread: float
    away_spread_odds: int = -110
    home_moneyline: Optional[int] = None
    away_moneyline: Optional[int] = None
    total: Optional[float] = None
    over_odds: int = -110
    under_odds: int = -110


class InjuryDTO(BaseModel):
    """Injury report data from provider."""
    team_external_id: str
    player_name: str
    player_position: str
    player_number: Optional[int] = None
    injury_status: str  # OUT, DOUBTFUL, QUESTIONABLE, PROBABLE
    injury_type: Optional[str] = None
    injury_description: Optional[str] = None
    season: int
    week: int
    report_date: datetime
    practice_status_wed: Optional[str] = None
    practice_status_thu: Optional[str] = None
    practice_status_fri: Optional[str] = None


class WeatherDTO(BaseModel):
    """Weather data from provider."""
    game_external_id: str
    forecast_time: datetime
    temperature: Optional[float] = None
    feels_like: Optional[float] = None
    wind_speed: Optional[float] = None
    wind_direction: Optional[str] = None
    precipitation_probability: Optional[float] = None
    precipitation_type: Optional[str] = None
    humidity: Optional[float] = None
    condition: Optional[str] = None
    indoor: bool = False
    provider: str = "mock"

# Add missing fields to GameDTO if not present
    home_spread: Optional[float] = None
    total_over_under: Optional[float] = None
