"""NFLverse adapter for real NFL data."""
import pandas as pd
from datetime import datetime
from typing import List, Optional
import logging

from api.adapters.base import ProviderAdapter, ProviderRegistry
from api.schemas.provider import TeamDTO, GameDTO, OddsDTO, InjuryDTO, WeatherDTO

logger = logging.getLogger(__name__)


class NFLverseAdapter(ProviderAdapter):
    """Adapter for NFLverse data - real historical NFL data."""
    
    def __init__(self, api_key: Optional[str] = None):
        super().__init__(api_key)
        self.games_url = "https://github.com/nflverse/nfldata/raw/master/data/games.csv"
        self._games_df = None
        self._teams_cache = None
    
    def _load_games_data(self):
        """Load the games CSV once and cache it."""
        if self._games_df is None:
            logger.info("Loading NFLverse games data...")
            self._games_df = pd.read_csv(self.games_url)
            logger.info(f"Loaded {len(self._games_df)} games from NFLverse")
        return self._games_df
    
    def get_teams(self) -> List[TeamDTO]:
        """Extract teams from games data."""
        if self._teams_cache:
            return self._teams_cache
            
        df = self._load_games_data()
        
        # Get unique teams
        teams = set()
        teams.update(df['home_team'].unique())
        teams.update(df['away_team'].unique())
        
        # Map team abbreviations to full info
        team_map = {
            'BUF': ('Bills', 'Buffalo', 'AFC', 'East'),
            'MIA': ('Dolphins', 'Miami', 'AFC', 'East'),
            'NE': ('Patriots', 'New England', 'AFC', 'East'),
            'NYJ': ('Jets', 'New York', 'AFC', 'East'),
            'BAL': ('Ravens', 'Baltimore', 'AFC', 'North'),
            'CIN': ('Bengals', 'Cincinnati', 'AFC', 'North'),
            'CLE': ('Browns', 'Cleveland', 'AFC', 'North'),
            'PIT': ('Steelers', 'Pittsburgh', 'AFC', 'North'),
            'HOU': ('Texans', 'Houston', 'AFC', 'South'),
            'IND': ('Colts', 'Indianapolis', 'AFC', 'South'),
            'JAX': ('Jaguars', 'Jacksonville', 'AFC', 'South'),
            'TEN': ('Titans', 'Tennessee', 'AFC', 'South'),
            'DEN': ('Broncos', 'Denver', 'AFC', 'West'),
            'KC': ('Chiefs', 'Kansas City', 'AFC', 'West'),
            'LV': ('Raiders', 'Las Vegas', 'AFC', 'West'),
            'OAK': ('Raiders', 'Oakland', 'AFC', 'West'),  # Historical
            'LAC': ('Chargers', 'Los Angeles', 'AFC', 'West'),
            'SD': ('Chargers', 'San Diego', 'AFC', 'West'),  # Historical
            'DAL': ('Cowboys', 'Dallas', 'NFC', 'East'),
            'NYG': ('Giants', 'New York', 'NFC', 'East'),
            'PHI': ('Eagles', 'Philadelphia', 'NFC', 'East'),
            'WAS': ('Commanders', 'Washington', 'NFC', 'East'),
            'CHI': ('Bears', 'Chicago', 'NFC', 'North'),
            'DET': ('Lions', 'Detroit', 'NFC', 'North'),
            'GB': ('Packers', 'Green Bay', 'NFC', 'North'),
            'MIN': ('Vikings', 'Minnesota', 'NFC', 'North'),
            'ATL': ('Falcons', 'Atlanta', 'NFC', 'South'),
            'CAR': ('Panthers', 'Carolina', 'NFC', 'South'),
            'NO': ('Saints', 'New Orleans', 'NFC', 'South'),
            'TB': ('Buccaneers', 'Tampa Bay', 'NFC', 'South'),
            'ARI': ('Cardinals', 'Arizona', 'NFC', 'West'),
            'LAR': ('Rams', 'Los Angeles', 'NFC', 'West'),
            'LA': ('Rams', 'Los Angeles', 'NFC', 'West'),  # Historical
            'STL': ('Rams', 'St. Louis', 'NFC', 'West'),  # Historical
            'SF': ('49ers', 'San Francisco', 'NFC', 'West'),
            'SEA': ('Seahawks', 'Seattle', 'NFC', 'West'),
        }
        
        team_dtos = []
        for abbr in teams:
            if abbr and abbr in team_map:
                name, city, conf, div = team_map[abbr]
                team_dtos.append(TeamDTO(
                    external_id=abbr,
                    name=name,
                    city=city,
                    abbreviation=abbr,
                    conference=conf,
                    division=div,
                    wins=0,
                    losses=0,
                    ties=0
                ))
        
        self._teams_cache = team_dtos
        return team_dtos
    
    def get_games(self, season: int, week: Optional[int] = None) -> List[GameDTO]:
        """Get real NFL games for a specific season/week."""
        df = self._load_games_data()
        
        # Filter by season
        season_df = df[df['season'] == season].copy()
        
        # Filter by week if specified
        if week:
            season_df = season_df[season_df['week'] == week]
        
        games = []
        for _, row in season_df.iterrows():
            # Parse date
            if pd.notna(row.get('gameday')):
                game_date = pd.to_datetime(row['gameday'])
            else:
                game_date = datetime(season, 9, 1)
            
            games.append(GameDTO(
                external_id=f"{row['game_id']}",
                season=season,
                season_type=row.get('game_type', 'REG'),
                week=int(row['week']),
                home_team_external_id=row['home_team'],
                away_team_external_id=row['away_team'],
                game_date=game_date,
                kickoff_time=game_date,
                status='FINAL' if pd.notna(row.get('home_score')) else 'SCHEDULED',
                home_score=int(row['home_score']) if pd.notna(row.get('home_score')) else None,
                away_score=int(row['away_score']) if pd.notna(row.get('away_score')) else None,
                stadium=row.get('stadium', ''),
                dome=row.get('roof', 'outdoors') != 'outdoors',
                surface=row.get('surface', 'grass'),
                temperature=float(row['temp']) if pd.notna(row.get('temp')) else None,
                wind_speed=float(row['wind']) if pd.notna(row.get('wind')) else None,
                home_spread=float(row['spread_line']) if pd.notna(row.get('spread_line')) else None,
                total_over_under=float(row['total_line']) if pd.notna(row.get('total_line')) else None
            ))
        
        logger.info(f"Loaded {len(games)} games for {season}" + (f" week {week}" if week else ""))
        return games
    
    def get_odds(self, season: int, week: int) -> List[OddsDTO]:
        """Get betting odds from game data."""
        games = self.get_games(season, week)
        odds_list = []
        
        for game in games:
            if game.home_spread is not None:
                odds_list.append(OddsDTO(
                    game_external_id=game.external_id,
                    provider="nflverse",
                    timestamp=game.game_date,
                    home_spread=game.home_spread,
                    away_spread=-game.home_spread,
                    home_moneyline=-110,  # Default
                    away_moneyline=-110,
                    total=game.total_over_under
                ))
        
        return odds_list
    
    def get_injuries(self, season: int, week: int) -> List[InjuryDTO]:
        """No injury data in basic games CSV."""
        return []
    
    def get_weather(self, game_external_id: str) -> Optional[WeatherDTO]:
        """Weather is in game data."""
        return None

def safe_string(value):
    """Convert value to string, handling NaN."""
    if pd.isna(value):
        return None
    return str(value) if value else None

def safe_float(value):
    """Convert value to float, handling NaN."""
    if pd.isna(value):
        return None
    try:
        return float(value)
    except:
        return None

# Register the adapter
ProviderRegistry.register("nflverse", NFLverseAdapter)