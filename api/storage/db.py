"""Database connection and session management."""
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker, Session
from sqlalchemy.pool import NullPool, QueuePool
from contextlib import contextmanager
from typing import Generator

from api.config import settings
from api.logging import get_logger

logger = get_logger(__name__)

# Create engine with connection pooling
engine = create_engine(
    settings.DATABASE_URL,
    poolclass=QueuePool,
    pool_size=settings.DATABASE_POOL_SIZE if hasattr(settings, 'DATABASE_POOL_SIZE') else 10,
    max_overflow=settings.DATABASE_MAX_OVERFLOW if hasattr(settings, 'DATABASE_MAX_OVERFLOW') else 20,
    pool_pre_ping=True,  # Verify connections before using
    echo=settings.ENVIRONMENT == "development",  # Log SQL in development
)

# Create session factory
SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine,
    class_=Session,
    expire_on_commit=False,
)


def get_db() -> Generator[Session, None, None]:
    """
    Dependency to get database session.
    Ensures proper cleanup after request.
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


@contextmanager
def get_db_context():
    """Context manager for database sessions."""
    db = SessionLocal()
    try:
        yield db
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def init_db() -> None:
    """Initialize database - create tables if they don't exist."""
    from api.storage.base import Base
    
    logger.info("Initializing database...")
    Base.metadata.create_all(bind=engine)
    logger.info("Database initialized successfully")


def check_db_connection() -> bool:
    """Check if database is accessible."""
    try:
        with engine.connect() as conn:
            conn.execute("SELECT 1")
        return True
    except Exception as e:
        logger.error(f"Database connection failed: {e}")
        return False
