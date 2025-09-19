"""Main FastAPI application."""
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, ORJSONResponse
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException

from api.config import settings
from api.app_logging import setup_logging, get_logger

setup_logging()
logger = get_logger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
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
    allow_origins=["http://localhost:8080", "http://localhost:3000", "http://localhost:5173"],
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


# Import and register routes
try:
    from api.routes import health
    app.include_router(health.router, prefix="/api", tags=["health"])
    logger.info("Health router registered")
except Exception as e:
    logger.error(f"Could not register health router: {e}")

try:
    from api.routes import ingest
    app.include_router(ingest.router, prefix="/api/ingest", tags=["ingest"])
    logger.info("Ingest router registered")
except Exception as e:
    logger.error(f"Could not register ingest router: {e}")

# IMPORTANT: Register predictions router at /api/predictions (not just /api)
try:
    from api.routes import predictions
    app.include_router(predictions.router, prefix="/api/predictions", tags=["predictions"])
    logger.info("Predictions router registered at /api/predictions")
except Exception as e:
    logger.error(f"Could not register predictions router: {e}")


@app.get("/")
async def root():
    return {"message": "NFL Prediction API", "documentation": "/docs"}
