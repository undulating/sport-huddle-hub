"""Application configuration."""
from typing import List
from functools import lru_cache
from pydantic import Field
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Environment
    ENVIRONMENT: str = Field(default="development")
    
    # Database
    DATABASE_URL: str = Field(...)
    
    # Redis
    REDIS_URL: str = Field(...)
    
    # Security
    SECRET_KEY: str = Field(..., min_length=32)
    ADMIN_USERNAME: str = Field(...)
    ADMIN_PASSWORD: str = Field(...)
    
    # Provider
    PROVIDER: str = Field(default="mock")
    PROVIDER_ODDS_API_KEY: str | None = Field(default=None)
    PROVIDER_STATS_API_KEY: str | None = Field(default=None)
    
    # Application
    TZ: str = Field(default="America/New_York")
    LOG_LEVEL: str = Field(default="INFO")
    CORS_ORIGINS: List[str] = Field(default=["http://localhost:5173", "http://localhost:3000"])
    
    class Config:
        env_file = ".env"
        case_sensitive = True


@lru_cache()
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
