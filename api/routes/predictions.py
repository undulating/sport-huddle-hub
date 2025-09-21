"""
Enhanced predictions.py with model selection support
Replace your api/routes/predictions.py with this version
"""
from typing import List, Optional, Literal
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session

from api.deps import get_db
from api.storage.models import Game, Team, ModelVersion
from api.models.elo_model import EloModel
from api.models.elo_recent_form import EloRecentFormModel
from api.app_logging import get_logger

logger = get_logger(__name__)
router = APIRouter()

# Model instances (singleton pattern for efficiency)
_models = {
    "elo": None,
    "elo_recent": None
}

def get_model(model_type: str):
    """Get or initialize the requested model."""
    global _models
    
    if model_type == "elo":
        if _models["elo"] is None:
            _models["elo"] = EloModel()
        return _models["elo"]
    elif model_type == "elo_recent":
        if _models["elo_recent"] is None:
            _models["elo_recent"] = EloRecentFormModel()
        return _models["elo_recent"]
    else:
        raise ValueError(f"Unknown model type: {model_type}")

class PredictionResponse(BaseModel):
    """Enhanced prediction response with model info."""
    game_id: int
    season: int
    week: int
    game_date: datetime
    kickoff_time: Optional[datetime]
    game_time: Optional[datetime]
    home_team: str
    away_team: str
    home_team_id: int
    away_team_id: int
    home_score: Optional[int]
    away_score: Optional[int]
    home_win_probability: float
    away_win_probability: float
    predicted_spread: float
    confidence: float  # Added confidence metric
    stadium: Optional[str]
    home_moneyline: Optional[int]
    away_moneyline: Optional[int]
    model_used: str  # Which model was used
    model_version: str  # Model version identifier

@router.get("/", response_model=List[PredictionResponse])
async def get_predictions(
    season: int = Query(..., description="NFL season year"),
    week: int = Query(..., description="NFL week number"),
    model: Literal["elo", "elo_recent"] = Query("elo", description="Model to use for predictions"),
    db: Session = Depends(get_db)
) -> List[PredictionResponse]:
    """
    Get predictions for a specific week using the selected model.
    
    Models available:
    - elo: Standard Elo rating system
    - elo_recent: Elo with recent form adjustments (last 3 games weighted 30%)
    """
    
    logger.info(f"Getting {model} predictions for {season} Week {week}")
    
    # Get the appropriate model
    prediction_model = get_model(model)
    prediction_model.load_ratings_from_db()
    
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
        
        # Get model predictions
        try:
            pred = prediction_model.predict_game(game.home_team_id, game.away_team_id)
            
            # Calculate confidence based on probability difference
            confidence = abs(pred['home_win_probability'] - 0.5) * 2
            
            predictions.append(PredictionResponse(
                game_id=game.id,
                season=game.season,
                week=game.week,
                game_date=game.game_date,
                kickoff_time=game.kickoff_time,
                game_time=game.kickoff_time or game.game_date,
                home_team=home_team.abbreviation,
                away_team=away_team.abbreviation,
                home_team_id=game.home_team_id,
                away_team_id=game.away_team_id,
                home_score=game.home_score,
                away_score=game.away_score,
                home_win_probability=pred['home_win_probability'],
                away_win_probability=pred['away_win_probability'],
                predicted_spread=pred['predicted_spread'],
                confidence=confidence,
                stadium=game.stadium,
                home_moneyline=game.home_moneyline,
                away_moneyline=game.away_moneyline,
                model_used=model,
                model_version=f"{model}_v1.0.0"
            ))
            
        except Exception as e:
            logger.error(f"Error predicting game {game.id}: {e}")
            continue
    
    logger.info(f"Returning {len(predictions)} predictions using {model} model")
    return predictions

@router.get("/models")
async def get_available_models():
    """Get list of available prediction models with their stats."""
    return [
        {
            "id": "elo",
            "name": "Standard Elo",
            "description": "Traditional Elo rating system",
            "accuracy": 0.848,  # Your 28/33 = 84.8% for 2025
            "historical_accuracy": 0.625,  # 62.5% on historical data
            "version": "1.0.0"
        },
        {
            "id": "elo_recent",
            "name": "Elo with Recent Form",
            "description": "Elo ratings with 30% weight on last 3 games",
            "accuracy": 0.830,  # Placeholder - update with actual
            "historical_accuracy": 0.635,  # Placeholder
            "version": "1.0.0"
        }
    ]

@router.get("/model-comparison")
async def compare_models(
    season: int = Query(..., description="NFL season year"),
    week: int = Query(..., description="NFL week number"),
    db: Session = Depends(get_db)
):
    """Compare predictions from all available models for a given week."""
    
    models_to_compare = ["elo", "elo_recent"]
    comparisons = {}
    
    for model_name in models_to_compare:
        # Get predictions for this model
        preds = await get_predictions(season, week, model_name, db)
        
        # Summarize predictions
        comparisons[model_name] = {
            "total_games": len(preds),
            "high_confidence_picks": sum(1 for p in preds if p.confidence > 0.7),
            "close_games": sum(1 for p in preds if p.confidence < 0.3),
            "predictions": [
                {
                    "game": f"{p.away_team} @ {p.home_team}",
                    "pick": p.home_team if p.home_win_probability > 0.5 else p.away_team,
                    "confidence": round(p.confidence * 100, 1)
                }
                for p in preds
            ]
        }
    
    return comparisons