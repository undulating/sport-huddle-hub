"""Common dependencies."""
from typing import Generator
from uuid import uuid4
from fastapi import Depends, Header, HTTPException, status
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from passlib.context import CryptContext
from sqlalchemy.orm import Session

from api.config import settings
from api.storage.db import get_db as get_database_session

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
security = HTTPBasic()


def get_request_id(x_request_id: str | None = Header(None)) -> str:
    """Get or generate request ID."""
    return x_request_id or str(uuid4())


def get_db() -> Generator[Session, None, None]:
    """Database session dependency."""
    yield from get_database_session()


def verify_admin(credentials: HTTPBasicCredentials = Depends(security)) -> str:
    """Verify admin credentials."""
    correct_username = credentials.username == settings.ADMIN_USERNAME
    correct_password = pwd_context.verify(
        credentials.password,
        pwd_context.hash(settings.ADMIN_PASSWORD)
    )
    
    if not (correct_username and correct_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials",
            headers={"WWW-Authenticate": "Basic"},
        )
    
    return credentials.username
