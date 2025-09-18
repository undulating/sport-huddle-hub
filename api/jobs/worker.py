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
