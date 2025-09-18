#!/bin/bash
# phase4-setup.sh
# Phase 4: Jobs, Scheduling, and Data Ingestion

set -e

echo "==================================="
echo "Phase 4: Jobs & Data Ingestion"
echo "==================================="

# Step 4.1: Create RQ Job Queue Setup
echo "Creating job queue infrastructure..."

cat > api/jobs/queue.py << 'EOF'
"""Redis Queue setup and helpers."""
import redis
from rq import Queue, Connection, Worker
from rq.job import Job
from typing import Optional, Any, Dict

from api.config import settings
from api.app_logging import get_logger

logger = get_logger(__name__)

# Create Redis connection
redis_conn = redis.from_url(settings.REDIS_URL)

# Create queues
high_queue = Queue('high', connection=redis_conn)
default_queue = Queue('default', connection=redis_conn)
low_queue = Queue('low', connection=redis_conn)


def enqueue_job(
    func,
    *args,
    queue_name: str = 'default',
    job_timeout: int = 300,
    **kwargs
) -> Job:
    """Enqueue a job to the specified queue."""
    queue_map = {
        'high': high_queue,
        'default': default_queue,
        'low': low_queue
    }
    
    queue = queue_map.get(queue_name, default_queue)
    
    job = queue.enqueue(
        func,
        *args,
        job_timeout=job_timeout,
        **kwargs
    )
    
    logger.info(f"Enqueued job {job.id} to {queue_name} queue")
    return job


def get_job_status(job_id: str) -> Optional[Dict[str, Any]]:
    """Get the status of a job."""
    try:
        job = Job.fetch(job_id, connection=redis_conn)
        return {
            'id': job.id,
            'status': job.get_status(),
            'result': job.result,
            'error': str(job.exc_info) if job.exc_info else None,
            'created_at': job.created_at,
            'started_at': job.started_at,
            'ended_at': job.ended_at
        }
    except Exception as e:
        logger.error(f"Error fetching job {job_id}: {e}")
        return None
EOF

cat > api/jobs/worker.py << 'EOF'
"""RQ Worker process."""
import sys
import redis
from rq import Worker, Queue, Connection

from api.config import settings
from api.app_logging import setup_logging, get_logger

setup_logging()
logger = get_logger(__name__)


def run_worker():
    """Run the RQ worker."""
    redis_conn = redis.from_url(settings.REDIS_URL)
    
    with Connection(redis_conn):
        queues = [
            Queue('high'),
            Queue('default'),
            Queue('low')
        ]
        
        worker = Worker(queues)
        logger.info(f"Starting worker for queues: {[q.name for q in queues]}")
        worker.work()


if __name__ == '__main__':
    run_worker()
EOF

# Step 4.2: Create Ingestion Jobs
echo "Creating data ingestion jobs..."

cat > api/storage/repositories/__init__.py << 'EOF'
"""Repository layer for database operations."""
EOF

cat > api/storage/repositories/ingest_repo.py << 'EOF'
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
EOF

cat > api/jobs/ingest.py << 'EOF'
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
EOF

# Create API routes for ingestion
echo "Creating ingestion API routes..."

cat > api/routes/ingest.py << 'EOF'
"""Data ingestion API routes."""
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from pydantic import BaseModel

from api.deps import verify_admin
from api.jobs.queue import enqueue_job
from api.jobs.ingest import job_backfill, job_sync
from api.app_logging import get_logger

logger = get_logger(__name__)

router = APIRouter()


class BackfillRequest(BaseModel):
    start_season: int = 2023
    end_season: int = 2024
    provider: Optional[str] = None


class SyncRequest(BaseModel):
    season: int
    week: int
    provider: Optional[str] = None


@router.post("/backfill")
async def trigger_backfill(
    request: BackfillRequest,
    background_tasks: BackgroundTasks,
    admin: str = Depends(verify_admin)
):
    """Trigger historical data backfill."""
    logger.info(f"Admin {admin} triggered backfill")
    
    # Enqueue the job
    job = enqueue_job(
        job_backfill,
        start_season=request.start_season,
        end_season=request.end_season,
        provider=request.provider,
        job_timeout=600  # 10 minutes
    )
    
    return {
        "message": "Backfill job enqueued",
        "job_id": job.id,
        "params": request.dict()
    }


@router.post("/sync")
async def trigger_sync(
    request: SyncRequest,
    admin: str = Depends(verify_admin)
):
    """Trigger data sync for current week."""
    logger.info(f"Admin {admin} triggered sync for {request.season} Week {request.week}")
    
    # Enqueue the job
    job = enqueue_job(
        job_sync,
        season=request.season,
        week=request.week,
        provider=request.provider,
        job_timeout=300  # 5 minutes
    )
    
    return {
        "message": "Sync job enqueued",
        "job_id": job.id,
        "params": request.dict()
    }


@router.get("/status/{job_id}")
async def get_job_status(job_id: str):
    """Get status of an ingestion job."""
    from api.jobs.queue import get_job_status
    
    status = get_job_status(job_id)
    if not status:
        raise HTTPException(status_code=404, detail="Job not found")
    
    return status
EOF

# Update app.py to include ingestion routes
echo "Updating app.py with ingestion routes..."

cat > api/update-app.py << 'EOF'
import sys
sys.path.append('/app')

# Read current app.py
with open('/app/api/app.py', 'r') as f:
    content = f.read()

# Add import for ingest router
import_line = "from api.routes import health, ingest"
content = content.replace("from api.routes import health", import_line)

# Add router inclusion
router_line = 'app.include_router(health.router, prefix="/api", tags=["health"])\napp.include_router(ingest.router, prefix="/api/ingest", tags=["ingest"])'
content = content.replace('app.include_router(health.router, prefix="/api", tags=["health"])', router_line)

# Write back
with open('/app/api/app.py', 'w') as f:
    f.write(content)

print("✅ App.py updated with ingest routes")
EOF

docker exec nflpred-api python /app/update-app.py

echo ""
echo "==================================="
echo "Phase 4 Complete!"
echo "==================================="
echo ""
echo "Next steps:"
echo "1. Restart API to load new routes"
echo "2. Test data ingestion"
EOF