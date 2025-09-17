#!/bin/bash
# complete-phase1-setup.sh
# This script creates all Phase 1 files and directories

set -e

echo "==================================="
echo "NFL Prediction System - Phase 1 Setup"
echo "==================================="

# Create directory structure
echo "Creating directory structure..."
mkdir -p api/{adapters,core,jobs,models,routes,schemas,scripts,storage,tests}
mkdir -p api/storage/{models,migrations/versions,repositories}
mkdir -p api/core/{auth,config,features,models,rate_limit}
mkdir -p api/fixtures/{2015,2016,2017,2018,2019,2020,2021,2022,2023,2024}
mkdir -p api/tests/{unit,integration,fixtures}
mkdir -p ops
mkdir -p logs
mkdir -p .github/workflows

# Create README.md
cat > README.md << 'EOF'
# NFL Prediction System

A comprehensive NFL game prediction system with real-time odds tracking, machine learning models, and automated predictions.

## Project Structure

```
/
├── api/                 # FastAPI backend
│   ├── adapters/       # External data providers
│   ├── core/           # Core business logic
│   ├── jobs/           # Background jobs (RQ)
│   ├── models/         # ML models (Elo, Skellam)
│   ├── routes/         # API endpoints
│   ├── schemas/        # Pydantic models
│   ├── storage/        # Database layer
│   └── tests/          # Test suite
├── web/                # React frontend (Vite + Tailwind)
├── ops/                # Docker & deployment configs
└── fixtures/           # Mock data for development
```

## Quick Start

### Prerequisites
- Python 3.11+
- Node.js 18+
- Docker Desktop
- Poetry (Python package manager)

### Development Setup

1. **Clone and install dependencies:**
```bash
# Backend
poetry install

# Frontend
cd web && npm install
```

2. **Start infrastructure:**
```bash
cd ops
docker compose up -d db redis
```

3. **Run migrations:**
```bash
docker compose exec api alembic upgrade head
```

4. **Start services:**
```bash
# Terminal 1: API
docker compose up api

# Terminal 2: Worker
docker compose up worker

# Terminal 3: Frontend
cd web && npm run dev
```

5. **Access the application:**
- Frontend: http://localhost:5173
- API: http://localhost:8000
- API Docs: http://localhost:8000/docs

## Environment Variables

Copy `.env.example` to `.env` and configure:

```bash
DATABASE_URL=postgresql://nflpred:nflpred123@localhost:5432/nflpred
REDIS_URL=redis://localhost:6379
SECRET_KEY=your-secret-key-here
ADMIN_USERNAME=admin
ADMIN_PASSWORD=secure-password
PROVIDER=mock  # or 'odds_api', 'sportsdataio'
```

## Testing

```bash
# Backend tests
pytest api/tests/

# Frontend tests
cd web && npm test
```

## License

MIT
EOF

# Create .gitignore
cat > .gitignore << 'EOF'
# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
env/
venv/
ENV/
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
*.egg-info/
.installed.cfg
*.egg
MANIFEST
.pytest_cache/
.coverage
htmlcov/
.tox/
.hypothesis/
*.log
poetry.lock

# Node
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
.pnpm-debug.log*
dist/
dist-ssr/
*.local

# Environment
.env
.env.local
.env.*.local
ops/.env.dev
!.env.example

# IDE
.vscode/
.idea/
*.swp
*.swo
*~
.DS_Store

# Docker
*.pid
.docker/

# Database
*.db
*.sqlite3
postgres_data/
redis_data/

# Logs
logs/
*.log

# Testing
coverage/
.nyc_output/

# Build artifacts
*.tsbuildinfo
EOF

# Create pyproject.toml
cat > pyproject.toml << 'EOF'
[tool.poetry]
name = "nfl-prediction-api"
version = "0.1.0"
description = "NFL Prediction System Backend API"
authors = ["NFL Prediction Team"]
readme = "README.md"
packages = [{include = "api"}]

[tool.poetry.dependencies]
python = "^3.11"
fastapi = "^0.109.0"
uvicorn = {extras = ["standard"], version = "^0.27.0"}
sqlalchemy = "^2.0.25"
alembic = "^1.13.1"
psycopg2-binary = "^2.9.9"
redis = "^5.0.1"
rq = "^1.16.1"
pydantic = "^2.5.3"
pydantic-settings = "^2.1.0"
httpx = "^0.26.0"
orjson = "^3.9.10"
python-jose = {extras = ["cryptography"], version = "^3.3.0"}
passlib = {extras = ["bcrypt"], version = "^1.7.4"}
python-multipart = "^0.0.6"
python-dateutil = "^2.8.2"
pandas = "^2.1.4"
numpy = "^1.26.3"
scipy = "^1.11.4"

[tool.poetry.group.dev.dependencies]
pytest = "^7.4.4"
pytest-asyncio = "^0.23.3"
pytest-cov = "^4.1.0"
black = "^23.12.1"
ruff = "^0.1.11"
isort = "^5.13.2"
mypy = "^1.8.0"
faker = "^22.0.0"
factory-boy = "^3.3.0"

[build-system]
requires = ["poetry-core"]
build-backend = "poetry.core.masonry.api"

[tool.black]
line-length = 88
target-version = ['py311']

[tool.isort]
profile = "black"
line_length = 88

[tool.ruff]
line-length = 88
select = ["E", "W", "F", "I", "B", "C4", "UP"]
ignore = ["E501", "B008", "B905"]

[tool.pytest.ini_options]
minversion = "7.0"
testpaths = ["api/tests"]
pythonpath = ["."]
EOF

# Create .env.example
cat > .env.example << 'EOF'
# Database
DATABASE_URL=postgresql://nflpred:nflpred123@localhost:5432/nflpred

# Redis
REDIS_URL=redis://localhost:6379/0

# Security
SECRET_KEY=your-secret-key-here-minimum-32-characters
ADMIN_USERNAME=admin
ADMIN_PASSWORD=secure-password-here

# Provider Configuration
PROVIDER=mock
PROVIDER_ODDS_API_KEY=
PROVIDER_STATS_API_KEY=

# Application
TZ=America/New_York
LOG_LEVEL=INFO
ENVIRONMENT=development

# Frontend
VITE_API_URL=http://localhost:8000
EOF

# Create ops/docker-compose.yml
cat > ops/docker-compose.yml << 'EOF'
version: '3.8'

services:
  db:
    image: postgres:15-alpine
    container_name: nflpred-db
    environment:
      POSTGRES_USER: nflpred
      POSTGRES_PASSWORD: nflpred123
      POSTGRES_DB: nflpred
      TZ: America/New_York
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U nflpred"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: nflpred-redis
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  api:
    build:
      context: ..
      dockerfile: ops/api.Dockerfile
    container_name: nflpred-api
    ports:
      - "8000:8000"
    environment:
      DATABASE_URL: postgresql://nflpred:nflpred123@db:5432/nflpred
      REDIS_URL: redis://redis:6379/0
      SECRET_KEY: dev-secret-key-change-in-production
      ADMIN_USERNAME: admin
      ADMIN_PASSWORD: admin123
      PROVIDER: mock
      TZ: America/New_York
      PYTHONUNBUFFERED: 1
      ENVIRONMENT: development
    depends_on:
      - db
      - redis
    volumes:
      - ../api:/app/api
    command: uvicorn api.app:app --host 0.0.0.0 --port 8000 --reload

  worker:
    build:
      context: ..
      dockerfile: ops/api.Dockerfile
    container_name: nflpred-worker
    environment:
      DATABASE_URL: postgresql://nflpred:nflpred123@db:5432/nflpred
      REDIS_URL: redis://redis:6379/0
      PROVIDER: mock
      TZ: America/New_York
      PYTHONUNBUFFERED: 1
    depends_on:
      - db
      - redis
    volumes:
      - ../api:/app/api
    command: python -m api.jobs.worker

volumes:
  postgres_data:
  redis_data:
EOF

# Create ops/api.Dockerfile
cat > ops/api.Dockerfile << 'EOF'
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    POETRY_VERSION=1.7.1 \
    POETRY_HOME="/opt/poetry" \
    POETRY_VIRTUALENVS_CREATE=false

ENV PATH="$POETRY_HOME/bin:$PATH"

WORKDIR /app

RUN apt-get update && apt-get install -y \
    gcc \
    postgresql-client \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN curl -sSL https://install.python-poetry.org | python3 -

COPY pyproject.toml poetry.lock* ./
RUN poetry install --no-root --no-dev || poetry install --no-root

COPY api/ ./api/
RUN mkdir -p /app/logs

EXPOSE 8000
CMD ["uvicorn", "api.app:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

# Create api/__init__.py
touch api/__init__.py

# Create api/app.py
cat > api/app.py << 'EOF'
"""Main FastAPI application."""
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, ORJSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from api.config import settings
from api.logging import setup_logging, get_logger
from api.routes import health

setup_logging()
logger = get_logger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifecycle."""
    logger.info(f"Starting NFL Prediction API - Environment: {settings.ENVIRONMENT}")
    yield
    logger.info("Shutting down NFL Prediction API")


app = FastAPI(
    title="NFL Prediction API",
    version="0.1.0",
    docs_url="/docs",
    redoc_url="/redoc",
    default_response_class=ORJSONResponse,
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(StarletteHTTPException)
async def http_exception_handler(request: Request, exc: StarletteHTTPException):
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": {"message": exc.detail, "type": "http_error"}},
    )


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={
            "error": {
                "message": "Validation error",
                "type": "validation_error",
                "details": exc.errors(),
            }
        },
    )


app.include_router(health.router, prefix="/api", tags=["health"])


@app.get("/")
async def root():
    return {"message": "NFL Prediction API", "documentation": "/docs"}
EOF

# Create api/config.py
cat > api/config.py << 'EOF'
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
EOF

# Create api/deps.py
cat > api/deps.py << 'EOF'
"""Common dependencies."""
from typing import Generator
from uuid import uuid4
from fastapi import Depends, Header, HTTPException, status
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from passlib.context import CryptContext
from api.config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
security = HTTPBasic()


def get_request_id(x_request_id: str | None = Header(None)) -> str:
    """Get or generate request ID."""
    return x_request_id or str(uuid4())


def get_db_session() -> Generator:
    """Database session dependency - to be implemented."""
    # TODO: Implement in Step 1.2
    yield None


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
EOF

# Create api/logging.py
cat > api/logging.py << 'EOF'
"""Logging configuration."""
import logging
import sys
import json
from datetime import datetime
from api.config import settings


class JSONFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        log_data = {
            "timestamp": datetime.utcnow().isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        
        if hasattr(record, "request_id"):
            log_data["request_id"] = record.request_id
            
        if record.exc_info:
            log_data["exception"] = self.formatException(record.exc_info)
            
        return json.dumps(log_data)


def setup_logging() -> None:
    """Configure application logging."""
    root_logger = logging.getLogger()
    root_logger.setLevel(getattr(logging, settings.LOG_LEVEL))
    root_logger.handlers = []
    
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(JSONFormatter())
    root_logger.addHandler(console_handler)
    
    logging.getLogger("uvicorn").setLevel(logging.INFO)
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)


def get_logger(name: str) -> logging.Logger:
    """Get logger instance."""
    return logging.getLogger(name)
EOF

# Create api/routes/__init__.py
touch api/routes/__init__.py

# Create api/routes/health.py
cat > api/routes/health.py << 'EOF'
"""Health check endpoints."""
from datetime import datetime
from typing import Dict, Any
from fastapi import APIRouter, Depends, status
from api.config import settings
from api.deps import get_request_id
from api.logging import get_logger

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
async def health(request_id: str = Depends(get_request_id)) -> Dict[str, Any]:
    """Detailed health check."""
    health_status = {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "version": "0.1.0",
        "environment": settings.ENVIRONMENT,
        "services": {
            "api": "healthy",
            "database": "pending",
            "redis": "pending",
        },
    }
    
    logger.info(f"Health check completed - {health_status['status']}")
    return health_status
EOF

# Create placeholder for jobs.worker
mkdir -p api/jobs
cat > api/jobs/__init__.py << 'EOF'
"""Background jobs module."""
EOF

cat > api/jobs/worker.py << 'EOF'
"""RQ Worker - placeholder for Phase 2."""
import time
import logging

logger = logging.getLogger(__name__)

if __name__ == "__main__":
    logger.info("Worker placeholder - will be implemented in Phase 2")
    while True:
        time.sleep(60)
EOF

# Make scripts executable
chmod +x ops/*.sh 2>/dev/null || true

echo "✅ All Phase 1 files created!"
echo ""
echo "Next steps:"
echo "1. Install Python dependencies: poetry install"
echo "2. Copy environment file: cp .env.example .env"
echo "3. Start services: cd ops && docker compose up -d db redis"
echo "4. Start API: cd ops && docker compose up api"
echo "5. Test health: curl http://localhost:8000/api/ping"
EOF