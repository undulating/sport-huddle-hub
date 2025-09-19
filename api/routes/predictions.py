"""Updated predictions route - api/routes/predictions.py"""
"""Prediction API endpoints with multiple model support."""
from typing import List, Optional, Dict
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session

from api.deps import get_db
from api.storage.models import Game, Team, ModelVersion
from api.models.elo_model import EloModel
from api.models.elo_recent_form import get_elo_recent_form_model
from api.app_logging import get_logger

logger = get_logger(__name__)
router = APIRouter()

# Global model instances
_elo_model: Optional[EloModel] = None
_models_cache: Dict = {}


def get_elo_model() -> EloModel:
    """Get or initialize the pure Elo model."""
    global _elo_model
    if _elo_model is None:
        _elo_model = EloModel()
    return _elo_model


def get_model_by_name(model_name: str):
    """Get the appropriate model based on name."""
    if model_name == "elo" or model_name == "elo_pure":
        model = get_elo_model()
        model.load_ratings_from_db()
        return model
    elif model_name == "elo_recent" or model_name == "elo_recent_form":
        return get_elo_recent_form_model()
    else:
        # Default to pure Elo for unknown models
        model = get_elo_model()
        model.load_ratings_from_db()
        return model


class PredictionResponse(BaseModel):
    """Enhanced prediction response with model info."""
    game_id: int
    season: int
    week: int
    game_date: datetime
    home_team: str
    away_team: str
    home_team_id: int
    away_team_id: int
    home_score: Optional[int]
    away_score: Optional[int]
    home_win_probability: float
    away_win_probability: float
    predicted_spread: float
    stadium: Optional[str]
    model_used: str
    home_form: Optional[Dict] = None  # Recent form data
    away_form: Optional[Dict] = None  # Recent form data


class ModelInfo(BaseModel):
    """Information about available models."""
    model_id: str
    display_name: str
    description: str
    accuracy: Optional[float] = None
    is_default: bool = False


@router.get("/models", response_model=List[ModelInfo])
async def get_available_models():
    """Get list of available prediction models."""
    models = [
        ModelInfo(
            model_id="elo",
            display_name="Pure Elo",
            description="Traditional Elo rating system based on historical performance",
            accuracy=0.625,  # You can dynamically calculate this
            is_default=True
        ),
        ModelInfo(
            model_id="elo_recent",
            display_name="Elo + Recent Form",
            description="Elo ratings adjusted for last 3 games performance and momentum",
            accuracy=None  # To be calculated once we have data
        )
    ]
    
    # You can add more models here as you create them:
    # - elo_injuries: "Elo + Injuries"
    # - ml_model: "Machine Learning"
    # - consensus: "Consensus Model"
    
    return models


@router.get("/", response_model=List[PredictionResponse])
async def get_predictions(
    season: int = Query(..., description="NFL season year"),
    week: int = Query(..., description="NFL week number"),
    model: str = Query("elo", description="Model to use for predictions"),
    db: Session = Depends(get_db)
) -> List[PredictionResponse]:
    """
    Get predictions for a specific week using the specified model.
    
    Available models:
    - elo: Pure Elo ratings
    - elo_recent: Elo with recent form adjustments
    """
    logger.info(f"Getting predictions for {season} Week {week} using model: {model}")
    
    # Get the appropriate model
    prediction_model = get_model_by_name(model)
    
    # Query games for the week
    games = db.query(Game).filter(
        Game.season == season,
        Game.week == week
    ).all()
    
    if not games:
        logger.warning(f"No games found for {season} Week {week}")
        return []
    
    predictions = []
    
    for game in games:
        # Get team information
        home_team = db.query(Team).filter(Team.id == game.home_team_id).first()
        away_team = db.query(Team).filter(Team.id == game.away_team_id).first()
        
        if not home_team or not away_team:
            logger.error(f"Teams not found for game {game.id}")
            continue
        
        # Get predictions from the selected model
        try:
            pred = prediction_model.predict_game(
                game.home_team_id, 
                game.away_team_id,
                game.game_date
            )
        except Exception as e:
            logger.error(f"Prediction error for game {game.id} using {model}: {e}")
            # Fallback to 50/50
            pred = {
                "home_win_probability": 0.5,
                "away_win_probability": 0.5,
                "predicted_spread": 0,
                "model_type": model
            }
        
        # Build response
        response = PredictionResponse(
            game_id=game.id,
            season=game.season,
            week=game.week,
            game_date=game.game_date,
            home_team=home_team.abbreviation,
            away_team=away_team.abbreviation,
            home_team_id=game.home_team_id,
            away_team_id=game.away_team_id,
            home_score=game.home_score,
            away_score=game.away_score,
            home_win_probability=pred["home_win_probability"],
            away_win_probability=pred["away_win_probability"],
            predicted_spread=pred["predicted_spread"],
            stadium=game.stadium,
            model_used=model
        )
        
        # Add form data if available (from recent form model)
        if 'home_form' in pred:
            response.home_form = pred['home_form']
        if 'away_form' in pred:
            response.away_form = pred['away_form']
        
        predictions.append(response)
    
    # Sort by game date/time
    predictions.sort(key=lambda x: x.game_date)
    
    logger.info(f"Returning {len(predictions)} predictions using {model} model")
    return predictions


@router.get("/compare")
async def compare_models(
    season: int = Query(..., description="NFL season year"),
    week: int = Query(..., description="NFL week number"),
    db: Session = Depends(get_db)
) -> Dict:
    """Compare predictions from all available models for a specific week."""
    models_to_compare = ["elo", "elo_recent"]
    comparisons = {}
    
    for model_name in models_to_compare:
        predictions = await get_predictions(season, week, model_name, db)
        comparisons[model_name] = [
            {
                "game": f"{p.away_team} @ {p.home_team}",
                "home_win_prob": round(p.home_win_probability * 100, 1),
                "spread": round(p.predicted_spread, 1)
            }
            for p in predictions
        ]
    
    return comparisons


@router.get("/hot-teams")
async def get_hot_teams(model: str = Query("elo_recent")) -> List[Dict]:
    """Get teams with the best recent form."""
    if model == "elo_recent":
        model_instance = get_elo_recent_form_model()
        return model_instance.get_hot_teams(top_n=5)
    else:
        return []


@router.get("/cold-teams") 
async def get_cold_teams(model: str = Query("elo_recent")) -> List[Dict]:
    """Get teams with the worst recent form."""
    if model == "elo_recent":
        model_instance = get_elo_recent_form_model()
        return model_instance.get_cold_teams(bottom_n=5)
    else:
        return []