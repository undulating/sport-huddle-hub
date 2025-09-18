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
