"""Data ingestion jobs."""
from typing import Optional
from datetime import datetime

from api.storage.db import get_db_context
from api.storage.repositories.ingest_repo import IngestRepository
from api.adapters.base import ProviderRegistry
from api.config import settings
from api.app_logging import get_logger

logger = get_logger(__name__)


def job_backfill(
    start_season: int = 2023,
    end_season: int = 2024,
    provider: Optional[str] = None
) -> dict:
    """Backfill historical data for seasons."""
    provider = provider or settings.PROVIDER
    logger.info(f"Starting backfill from {start_season} to {end_season} using {provider}")
    
    results = {
        'seasons_processed': 0,
        'teams_added': 0,
        'games_added': 0,
        'odds_added': 0,
        'injuries_added': 0,
        'errors': []
    }
    
    try:
        # Get provider adapter
        adapter = ProviderRegistry.get_adapter(provider)
        
        with get_db_context() as db:
            repo = IngestRepository(db)
            
            # Load teams first
            teams = adapter.get_teams()
            results['teams_added'] = repo.upsert_teams(teams)
            
            # Process each season
            for season in range(start_season, end_season + 1):
                logger.info(f"Processing season {season}")
                
                # Get all games for the season
                games = adapter.get_games(season)
                results['games_added'] += repo.upsert_games(games)
                
                # Get odds for each week
                for week in range(1, 18):  # Regular season weeks
                    odds = adapter.get_odds(season, week)
                    results['odds_added'] += repo.upsert_odds(odds)
                    
                    injuries = adapter.get_injuries(season, week)
                    results['injuries_added'] += repo.upsert_injuries(injuries)
                
                results['seasons_processed'] += 1
    
    except Exception as e:
        logger.error(f"Backfill error: {e}")
        results['errors'].append(str(e))
    
    logger.info(f"Backfill complete: {results}")
    return results


def job_sync(season: int, week: int, provider: Optional[str] = None) -> dict:
    """Sync current week data."""
    provider = provider or settings.PROVIDER
    logger.info(f"Syncing {season} Week {week} using {provider}")
    
    results = {
        'games_updated': 0,
        'odds_added': 0,
        'injuries_added': 0,
        'weather_added': 0,
        'timestamp': datetime.utcnow().isoformat()
    }
    
    try:
        adapter = ProviderRegistry.get_adapter(provider)
        
        with get_db_context() as db:
            repo = IngestRepository(db)
            
            # Update games
            games = adapter.get_games(season, week)
            results['games_updated'] = repo.upsert_games(games)
            
            # Update odds
            odds = adapter.get_odds(season, week)
            results['odds_added'] = repo.upsert_odds(odds)
            
            # Update injuries
            injuries = adapter.get_injuries(season, week)
            results['injuries_added'] = repo.upsert_injuries(injuries)
            
            # Update weather for each game
            weather_records = []
            for game in games:
                weather = adapter.get_weather(game.external_id)
                if weather:
                    weather_records.append(weather)
            
            if weather_records:
                results['weather_added'] = repo.upsert_weather(weather_records)
    
    except Exception as e:
        logger.error(f"Sync error: {e}")
        results['error'] = str(e)
    
    logger.info(f"Sync complete: {results}")
    return results
