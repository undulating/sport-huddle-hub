"""Main FastAPI application."""
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, ORJSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from api.config import settings
from api.app_logging import setup_logging, get_logger
from api.routes import health, ingest

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
app.include_router(ingest.router, prefix="/api/ingest", tags=["ingest"])


@app.get("/")
async def root():
    return {"message": "NFL Prediction API", "documentation": "/docs"}

from api.routes import predictions
app.include_router(predictions.router, prefix="/api/predictions", tags=["predictions"])

