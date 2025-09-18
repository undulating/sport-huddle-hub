"""Health check endpoints."""
from datetime import datetime
from typing import Dict, Any
from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from api.config import settings
from api.deps import get_request_id, get_db
from api.storage.db import check_db_connection
from api.app_logging import get_logger

logger = get_logger(__name__)
router = APIRouter()


@router.get("/ping")
async def ping(request_id: str = Depends(get_request_id)) -> Dict[str, Any]:
    """Simple health check."""
    logger.debug(f"Health check requested - request_id: {request_id}")
    return {
        "status": "ok",
        "message": "NFL Prediction API is running",
        "timestamp": datetime.utcnow().isoformat(),
        "version": "0.1.0",
        "environment": settings.ENVIRONMENT,
    }


@router.get("/health")
async def health(
    request_id: str = Depends(get_request_id),
    db: Session = Depends(get_db)
) -> Dict[str, Any]:
    """Detailed health check."""
    health_status = {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "version": "0.1.0",
        "environment": settings.ENVIRONMENT,
        "services": {
            "api": "healthy",
            "database": "unknown",
            "redis": "pending",
        },
    }
    
    # Check database
    try:
        db.execute("SELECT 1")
        health_status["services"]["database"] = "healthy"
    except Exception as e:
        health_status["services"]["database"] = "unhealthy"
        health_status["status"] = "degraded"
        logger.error(f"Database health check failed: {e}")
    
    logger.info(f"Health check completed - {health_status['status']}")
    return health_status
