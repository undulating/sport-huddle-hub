#!/bin/bash
# phase3-setup.sh
# Phase 3: Create Provider Adapters and Mock Data

set -e

echo "==================================="
echo "Phase 3: Provider Adapters & Mock Data"
echo "==================================="

# Step 3.1: Create DTOs and Adapter Protocol
echo "Creating provider DTOs and base adapter..."

mkdir -p api/schemas
cat > api/schemas/__init__.py << 'EOF'
"""Schema definitions."""
EOF

cat > api/schemas/provider.py << 'EOF'
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
EOF

cat > api/adapters/__init__.py << 'EOF'
"""Provider adapters."""
EOF

cat > api/adapters/base.py << 'EOF'
"""Base adapter protocol for data providers."""
from abc import ABC, abstractmethod
from typing import List, Optional, Dict, Any
from datetime import datetime

from api.schemas.provider import (
    TeamDTO, GameDTO, OddsDTO, InjuryDTO, WeatherDTO
)


class ProviderAdapter(ABC):
    """Abstract base class for provider adapters."""
    
    def __init__(self, api_key: Optional[str] = None):
        """Initialize adapter with optional API key."""
        self.api_key = api_key
        self.provider_name = self.__class__.__name__.replace("Adapter", "")
    
    @abstractmethod
    def get_teams(self) -> List[TeamDTO]:
        """Get all NFL teams."""
        pass
    
    @abstractmethod
    def get_games(self, season: int, week: Optional[int] = None) -> List[GameDTO]:
        """Get games for a season/week."""
        pass
    
    @abstractmethod
    def get_odds(self, season: int, week: int) -> List[OddsDTO]:
        """Get betting odds for games."""
        pass
    
    @abstractmethod
    def get_injuries(self, season: int, week: int) -> List[InjuryDTO]:
        """Get injury reports."""
        pass
    
    @abstractmethod
    def get_weather(self, game_external_id: str) -> Optional[WeatherDTO]:
        """Get weather forecast for a game."""
        pass


class ProviderRegistry:
    """Registry for provider adapters."""
    
    _adapters: Dict[str, type] = {}
    
    @classmethod
    def register(cls, name: str, adapter_class: type):
        """Register a provider adapter."""
        cls._adapters[name] = adapter_class
    
    @classmethod
    def get_adapter(cls, name: str, **kwargs) -> ProviderAdapter:
        """Get an instance of a provider adapter."""
        if name not in cls._adapters:
            raise ValueError(f"Unknown provider: {name}")
        return cls._adapters[name](**kwargs)
    
    @classmethod
    def list_providers(cls) -> List[str]:
        """List available providers."""
        return list(cls._adapters.keys())
EOF

# Step 3.2: Create Mock Provider Adapter
echo "Creating mock provider adapter..."

cat > api/adapters/mock_adapter.py << 'EOF'
"""Mock provider adapter for development."""
import json
import random
from pathlib import Path
from datetime import datetime, timedelta
from typing import List, Optional

from api.adapters.base import ProviderAdapter, ProviderRegistry
from api.schemas.provider import (
    TeamDTO, GameDTO, OddsDTO, InjuryDTO, WeatherDTO
)


class MockAdapter(ProviderAdapter):
    """Mock data provider for development and testing."""
    
    def __init__(self, api_key: Optional[str] = None):
        super().__init__(api_key)
        self.fixtures_path = Path("/app/api/fixtures")
        
        # NFL Teams data
        self.teams_data = self._load_teams_data()
    
    def _load_teams_data(self) -> List[dict]:
        """Load NFL teams data."""
        return [
            # AFC East
            {"external_id": "BUF", "name": "Bills", "city": "Buffalo", "abbreviation": "BUF", 
             "conference": "AFC", "division": "East", "primary_color": "#00338D", "secondary_color": "#C60C30"},
            {"external_id": "MIA", "name": "Dolphins", "city": "Miami", "abbreviation": "MIA",
             "conference": "AFC", "division": "East", "primary_color": "#008E97", "secondary_color": "#FC4C02"},
            {"external_id": "NE", "name": "Patriots", "city": "New England", "abbreviation": "NE",
             "conference": "AFC", "division": "East", "primary_color": "#002244", "secondary_color": "#C60C30"},
            {"external_id": "NYJ", "name": "Jets", "city": "New York", "abbreviation": "NYJ",
             "conference": "AFC", "division": "East", "primary_color": "#125740", "secondary_color": "#FFFFFF"},
            
            # AFC North
            {"external_id": "BAL", "name": "Ravens", "city": "Baltimore", "abbreviation": "BAL",
             "conference": "AFC", "division": "North", "primary_color": "#241773", "secondary_color": "#000000"},
            {"external_id": "CIN", "name": "Bengals", "city": "Cincinnati", "abbreviation": "CIN",
             "conference": "AFC", "division": "North", "primary_color": "#FB4F14", "secondary_color": "#000000"},
            {"external_id": "CLE", "name": "Browns", "city": "Cleveland", "abbreviation": "CLE",
             "conference": "AFC", "division": "North", "primary_color": "#311D00", "secondary_color": "#FF3C00"},
            {"external_id": "PIT", "name": "Steelers", "city": "Pittsburgh", "abbreviation": "PIT",
             "conference": "AFC", "division": "North", "primary_color": "#FFB612", "secondary_color": "#101820"},
            
            # AFC South
            {"external_id": "HOU", "name": "Texans", "city": "Houston", "abbreviation": "HOU",
             "conference": "AFC", "division": "South", "primary_color": "#03202F", "secondary_color": "#A71930"},
            {"external_id": "IND", "name": "Colts", "city": "Indianapolis", "abbreviation": "IND",
             "conference": "AFC", "division": "South", "primary_color": "#002C5F", "secondary_color": "#A2AAAD"},
            {"external_id": "JAX", "name": "Jaguars", "city": "Jacksonville", "abbreviation": "JAX",
             "conference": "AFC", "division": "South", "primary_color": "#101820", "secondary_color": "#D7A22A"},
            {"external_id": "TEN", "name": "Titans", "city": "Tennessee", "abbreviation": "TEN",
             "conference": "AFC", "division": "South", "primary_color": "#0C2340", "secondary_color": "#4B92DB"},
            
            # AFC West
            {"external_id": "DEN", "name": "Broncos", "city": "Denver", "abbreviation": "DEN",
             "conference": "AFC", "division": "West", "primary_color": "#FB4F14", "secondary_color": "#002244"},
            {"external_id": "KC", "name": "Chiefs", "city": "Kansas City", "abbreviation": "KC",
             "conference": "AFC", "division": "West", "primary_color": "#E31837", "secondary_color": "#FFB81C"},
            {"external_id": "LV", "name": "Raiders", "city": "Las Vegas", "abbreviation": "LV",
             "conference": "AFC", "division": "West", "primary_color": "#000000", "secondary_color": "#A5ACAF"},
            {"external_id": "LAC", "name": "Chargers", "city": "Los Angeles", "abbreviation": "LAC",
             "conference": "AFC", "division": "West", "primary_color": "#0080C6", "secondary_color": "#FFC20E"},
            
            # NFC East
            {"external_id": "DAL", "name": "Cowboys", "city": "Dallas", "abbreviation": "DAL",
             "conference": "NFC", "division": "East", "primary_color": "#041E42", "secondary_color": "#869397"},
            {"external_id": "NYG", "name": "Giants", "city": "New York", "abbreviation": "NYG",
             "conference": "NFC", "division": "East", "primary_color": "#0B2265", "secondary_color": "#A71930"},
            {"external_id": "PHI", "name": "Eagles", "city": "Philadelphia", "abbreviation": "PHI",
             "conference": "NFC", "division": "East", "primary_color": "#004C54", "secondary_color": "#A5ACAF"},
            {"external_id": "WAS", "name": "Commanders", "city": "Washington", "abbreviation": "WAS",
             "conference": "NFC", "division": "East", "primary_color": "#5A1414", "secondary_color": "#FFB612"},
            
            # NFC North
            {"external_id": "CHI", "name": "Bears", "city": "Chicago", "abbreviation": "CHI",
             "conference": "NFC", "division": "North", "primary_color": "#0B162A", "secondary_color": "#C83803"},
            {"external_id": "DET", "name": "Lions", "city": "Detroit", "abbreviation": "DET",
             "conference": "NFC", "division": "North", "primary_color": "#0076B6", "secondary_color": "#B0B7BC"},
            {"external_id": "GB", "name": "Packers", "city": "Green Bay", "abbreviation": "GB",
             "conference": "NFC", "division": "North", "primary_color": "#203731", "secondary_color": "#FFB612"},
            {"external_id": "MIN", "name": "Vikings", "city": "Minnesota", "abbreviation": "MIN",
             "conference": "NFC", "division": "North", "primary_color": "#4F2683", "secondary_color": "#FFC62F"},
            
            # NFC South
            {"external_id": "ATL", "name": "Falcons", "city": "Atlanta", "abbreviation": "ATL",
             "conference": "NFC", "division": "South", "primary_color": "#A71930", "secondary_color": "#000000"},
            {"external_id": "CAR", "name": "Panthers", "city": "Carolina", "abbreviation": "CAR",
             "conference": "NFC", "division": "South", "primary_color": "#0085CA", "secondary_color": "#101820"},
            {"external_id": "NO", "name": "Saints", "city": "New Orleans", "abbreviation": "NO",
             "conference": "NFC", "division": "South", "primary_color": "#D3BC8D", "secondary_color": "#101820"},
            {"external_id": "TB", "name": "Buccaneers", "city": "Tampa Bay", "abbreviation": "TB",
             "conference": "NFC", "division": "South", "primary_color": "#D50A0A", "secondary_color": "#34302B"},
            
            # NFC West
            {"external_id": "ARI", "name": "Cardinals", "city": "Arizona", "abbreviation": "ARI",
             "conference": "NFC", "division": "West", "primary_color": "#97233F", "secondary_color": "#000000"},
            {"external_id": "LAR", "name": "Rams", "city": "Los Angeles", "abbreviation": "LAR",
             "conference": "NFC", "division": "West", "primary_color": "#003594", "secondary_color": "#FFA300"},
            {"external_id": "SF", "name": "49ers", "city": "San Francisco", "abbreviation": "SF",
             "conference": "NFC", "division": "West", "primary_color": "#AA0000", "secondary_color": "#B3995D"},
            {"external_id": "SEA", "name": "Seahawks", "city": "Seattle", "abbreviation": "SEA",
             "conference": "NFC", "division": "West", "primary_color": "#002244", "secondary_color": "#69BE28"},
        ]
    
    def get_teams(self) -> List[TeamDTO]:
        """Get all NFL teams."""
        teams = []
        for team_data in self.teams_data:
            # Add random wins/losses for current season
            wins = random.randint(0, 10)
            losses = random.randint(0, 10)
            teams.append(TeamDTO(
                **team_data,
                wins=wins,
                losses=losses,
                ties=0,
                stadium_name=f"{team_data['city']} Stadium"
            ))
        return teams
    
    def get_games(self, season: int, week: Optional[int] = None) -> List[GameDTO]:
        """Generate mock games for a season/week."""
        games = []
        
        # For simplicity, generate a few games per week
        weeks = [week] if week else range(1, 18)  # Regular season weeks
        
        for w in weeks:
            # Generate 4-6 mock games per week
            game_date = datetime(season, 9, 1) + timedelta(weeks=w-1)
            
            # Sample matchups
            matchups = [
                ("KC", "BUF"), ("DAL", "PHI"), ("GB", "CHI"), 
                ("SF", "SEA"), ("NE", "MIA"), ("BAL", "PIT")
            ]
            
            for i, (home, away) in enumerate(matchups[:4]):
                game_time = game_date.replace(hour=13 if i < 2 else 16, minute=0)
                
                games.append(GameDTO(
                    external_id=f"{season}-{w:02d}-{home}-{away}",
                    season=season,
                    season_type="REG",
                    week=w,
                    home_team_external_id=home,
                    away_team_external_id=away,
                    game_date=game_time,
                    kickoff_time=game_time,
                    status="SCHEDULED" if game_time > datetime.now() else "FINAL",
                    home_score=random.randint(14, 35) if game_time < datetime.now() else None,
                    away_score=random.randint(14, 35) if game_time < datetime.now() else None,
                    stadium=f"{home} Stadium",
                    dome=random.choice([True, False]),
                    surface=random.choice(["grass", "turf"])
                ))
        
        return games
    
    def get_odds(self, season: int, week: int) -> List[OddsDTO]:
        """Generate mock odds for games."""
        odds = []
        games = self.get_games(season, week)
        
        for game in games:
            # Generate odds for each game
            home_spread = random.choice([-7, -3.5, -3, -1, 1, 3, 3.5, 7])
            total = random.choice([42.5, 44, 45.5, 47, 48.5, 50, 51.5])
            
            odds.append(OddsDTO(
                game_external_id=game.external_id,
                provider="mock_sportsbook",
                timestamp=datetime.now(),
                home_spread=home_spread,
                away_spread=-home_spread,
                home_moneyline=-150 if home_spread < 0 else 130,
                away_moneyline=130 if home_spread < 0 else -150,
                total=total
            ))
        
        return odds
    
    def get_injuries(self, season: int, week: int) -> List[InjuryDTO]:
        """Generate mock injury reports."""
        injuries = []
        statuses = ["OUT", "DOUBTFUL", "QUESTIONABLE", "PROBABLE"]
        positions = ["QB", "RB", "WR", "TE", "OL", "DL", "LB", "CB", "S"]
        
        # Generate 2-3 injuries per team (sample)
        for team in random.sample(self.teams_data, 8):
            for i in range(random.randint(1, 3)):
                injuries.append(InjuryDTO(
                    team_external_id=team["external_id"],
                    player_name=f"Player {i+1}",
                    player_position=random.choice(positions),
                    player_number=random.randint(1, 99),
                    injury_status=random.choice(statuses),
                    injury_type=random.choice(["knee", "ankle", "shoulder", "hamstring"]),
                    season=season,
                    week=week,
                    report_date=datetime.now()
                ))
        
        return injuries
    
    def get_weather(self, game_external_id: str) -> Optional[WeatherDTO]:
        """Generate mock weather data."""
        return WeatherDTO(
            game_external_id=game_external_id,
            forecast_time=datetime.now(),
            temperature=random.randint(30, 85),
            feels_like=random.randint(25, 90),
            wind_speed=random.randint(0, 20),
            wind_direction=random.choice(["N", "NE", "E", "SE", "S", "SW", "W", "NW"]),
            precipitation_probability=random.randint(0, 30),
            humidity=random.randint(40, 80),
            condition=random.choice(["clear", "cloudy", "partly cloudy", "light rain"])
        )


# Register the mock adapter
ProviderRegistry.register("mock", MockAdapter)
EOF

echo "✅ Provider adapters created"

# Create a test script
cat > test-providers.py << 'EOF'
#!/usr/bin/env python3
"""Test provider adapters."""
import sys
sys.path.append('.')

from api.adapters.base import ProviderRegistry
from api.adapters.mock_adapter import MockAdapter

def test_providers():
    print("Testing Provider Adapters...")
    
    # Test registry
    providers = ProviderRegistry.list_providers()
    print(f"✅ Available providers: {providers}")
    
    # Get mock adapter
    adapter = ProviderRegistry.get_adapter("mock")
    print(f"✅ Got adapter: {adapter.provider_name}")
    
    # Test getting teams
    teams = adapter.get_teams()
    print(f"✅ Loaded {len(teams)} teams")
    print(f"   Sample team: {teams[0].name} ({teams[0].abbreviation})")
    
    # Test getting games
    games = adapter.get_games(2024, 1)
    print(f"✅ Loaded {len(games)} games for Week 1")
    if games:
        print(f"   Sample game: {games[0].home_team_external_id} vs {games[0].away_team_external_id}")
    
    # Test getting odds
    odds = adapter.get_odds(2024, 1)
    print(f"✅ Loaded {len(odds)} odds records")
    if odds:
        print(f"   Sample spread: {odds[0].home_spread}")
    
    # Test getting injuries
    injuries = adapter.get_injuries(2024, 1)
    print(f"✅ Loaded {len(injuries)} injury reports")
    
    print("\n✅ Phase 3 Provider Setup Complete!")

if __name__ == "__main__":
    test_providers()
EOF

echo ""
echo "==================================="
echo "Phase 3 Setup Complete!"
echo "==================================="
echo ""
echo "Test the providers:"
echo "python test-providers.py"
EOF