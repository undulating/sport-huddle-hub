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
