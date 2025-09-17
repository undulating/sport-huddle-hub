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
