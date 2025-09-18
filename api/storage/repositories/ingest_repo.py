"""Repository for data ingestion."""
import hashlib
from typing import List, Optional, Dict, Any
from datetime import datetime
from sqlalchemy.orm import Session
from sqlalchemy.dialects.postgresql import insert

from api.storage.models import Team, Game, Odds, Injury, Weather
from api.schemas.provider import TeamDTO, GameDTO, OddsDTO, InjuryDTO, WeatherDTO
from api.app_logging import get_logger

logger = get_logger(__name__)


class IngestRepository:
    """Handle data ingestion with deduplication."""
    
    def __init__(self, db: Session):
        self.db = db
    
    def _generate_checksum(self, data: Dict[str, Any]) -> str:
        """Generate checksum for deduplication."""
        data_str = str(sorted(data.items()))
        return hashlib.sha256(data_str.encode()).hexdigest()
    
    def upsert_teams(self, teams: List[TeamDTO]) -> int:
        """Upsert teams data."""
        count = 0
        for team_dto in teams:
            team_data = team_dto.dict()
            
            # Check if team exists
            team = self.db.query(Team).filter(
                Team.external_id == team_data['external_id']
            ).first()
            
            if team:
                # Update existing team
                for key, value in team_data.items():
                    setattr(team, key, value)
            else:
                # Create new team
                team = Team(**team_data)
                self.db.add(team)
                count += 1
        
        self.db.commit()
        logger.info(f"Upserted {count} new teams")
        return count
    
    def upsert_games(self, games: List[GameDTO]) -> int:
        """Upsert games data."""
        count = 0
        
        for game_dto in games:
            game_data = game_dto.dict()
            
            # Get team IDs
            home_team = self.db.query(Team).filter(
                Team.external_id == game_data.pop('home_team_external_id')
            ).first()
            away_team = self.db.query(Team).filter(
                Team.external_id == game_data.pop('away_team_external_id')
            ).first()
            
            if not home_team or not away_team:
                logger.warning(f"Teams not found for game {game_dto.external_id}")
                continue
            
            game_data['home_team_id'] = home_team.id
            game_data['away_team_id'] = away_team.id
            
            # Generate checksum
            game_data['checksum'] = self._generate_checksum(game_data)
            
            # Check if game exists
            game = self.db.query(Game).filter(
                Game.external_id == game_data['external_id']
            ).first()
            
            if game:
                # Update if checksum different
                if game.checksum != game_data['checksum']:
                    for key, value in game_data.items():
                        setattr(game, key, value)
                    game.updated_at = datetime.utcnow()
            else:
                # Create new game
                game = Game(**game_data)
                self.db.add(game)
                count += 1
        
        self.db.commit()
        logger.info(f"Upserted {count} new games")
        return count
    
    def upsert_odds(self, odds: List[OddsDTO]) -> int:
        """Upsert odds data."""
        count = 0
        
        for odds_dto in odds:
            odds_data = odds_dto.dict()
            
            # Get game ID
            game = self.db.query(Game).filter(
                Game.external_id == odds_data.pop('game_external_id')
            ).first()
            
            if not game:
                logger.warning(f"Game not found for odds {odds_dto.game_external_id}")
                continue
            
            odds_data['game_id'] = game.id
            odds_data['checksum'] = self._generate_checksum(odds_data)
            
            # Check for existing odds with same checksum
            existing = self.db.query(Odds).filter(
                Odds.checksum == odds_data['checksum']
            ).first()
            
            if not existing:
                odds_record = Odds(**odds_data)
                self.db.add(odds_record)
                count += 1
        
        self.db.commit()
        logger.info(f"Added {count} new odds records")
        return count
    
    def upsert_injuries(self, injuries: List[InjuryDTO]) -> int:
        """Upsert injury data."""
        count = 0
        
        for injury_dto in injuries:
            injury_data = injury_dto.dict()
            
            # Get team ID
            team = self.db.query(Team).filter(
                Team.external_id == injury_data.pop('team_external_id')
            ).first()
            
            if not team:
                logger.warning(f"Team not found for injury {injury_dto.team_external_id}")
                continue
            
            injury_data['team_id'] = team.id
            injury_data['checksum'] = self._generate_checksum(injury_data)
            
            # Check for existing injury with same checksum
            existing = self.db.query(Injury).filter(
                Injury.checksum == injury_data['checksum']
            ).first()
            
            if not existing:
                injury_record = Injury(**injury_data)
                self.db.add(injury_record)
                count += 1
        
        self.db.commit()
        logger.info(f"Added {count} new injury records")
        return count
    
    def upsert_weather(self, weather_list: List[WeatherDTO]) -> int:
        """Upsert weather data."""
        count = 0
        
        for weather_dto in weather_list:
            weather_data = weather_dto.dict()
            
            # Get game ID
            game = self.db.query(Game).filter(
                Game.external_id == weather_data.pop('game_external_id')
            ).first()
            
            if not game:
                continue
            
            weather_data['game_id'] = game.id
            weather_data['checksum'] = self._generate_checksum(weather_data)
            
            # Check for existing weather with same checksum
            existing = self.db.query(Weather).filter(
                Weather.checksum == weather_data['checksum']
            ).first()
            
            if not existing:
                weather_record = Weather(**weather_data)
                self.db.add(weather_record)
                count += 1
        
        self.db.commit()
        logger.info(f"Added {count} new weather records")
        return count
