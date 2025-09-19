"""API routes module."""
from . import health
from . import predictions
from . import ingest

__all__ = ["health", "predictions", "ingest"]
