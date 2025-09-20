"""Optimized prediction API endpoints - no training on request."""
from typing import List, Optional
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session

from api.deps import get_db
from api.storage.models import Game, Team, ModelVersion
from api.models.elo_model import EloModel
from api.app_logging import get_logger
from api.adapters.base import ProviderRegistry  # Add this import
from api.config import settings  # Add this import

logger = get_logger(__name__)
router = APIRouter()

# Global Elo model instance
_elo_model: Optional[EloModel] = None

def get_elo_model() -> EloModel:
    """Get or initialize the Elo model."""
    global _elo_model
    if _elo_model is None:
        _elo_model = EloModel()
    return _elo_model

class PredictionResponse(BaseModel):
    """Simple prediction response."""
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

class TeamResponse(BaseModel):  # Add this class
    """Team response model."""
    abbreviation: str
    name: str
    city: str
    conference: str
    division: str
    elo_rating: Optional[float] = None

@router.get("/", response_model=List[PredictionResponse])
async def get_predictions(
    season: int = Query(..., description="NFL season year"),
    week: int = Query(..., description="NFL week number"),
    db: Session = Depends(get_db)
) -> List[PredictionResponse]:
    """Get predictions for a specific week."""
    logger.info(f"Getting predictions for {season} Week {week}")
    
    # Get or initialize Elo model
    elo_model = get_elo_model()
    elo_model.load_ratings_from_db()
    
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
        
        # Get Elo predictions
        try:
            elo_pred = elo_model.predict_game(game.home_team_id, game.away_team_id)
        except Exception as e:
            logger.error(f"Prediction error for game {game.id}: {e}")
            elo_pred = {
                "home_win_probability": 0.5,
                "away_win_probability": 0.5,
                "predicted_spread": 0
            }
        
        predictions.append(PredictionResponse(
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
            home_win_probability=elo_pred["home_win_probability"],
            away_win_probability=elo_pred["away_win_probability"],
            predicted_spread=elo_pred["predicted_spread"],
            stadium=game.stadium
        ))
    
    # Sort by game date/time
    predictions.sort(key=lambda x: x.game_date)
    
    logger.info(f"Returning {len(predictions)} predictions")
    return predictions


@router.get("/teams", response_model=List[TeamResponse])  # ADD THIS NEW ENDPOINT
async def get_teams(
    db: Session = Depends(get_db)
) -> List[TeamResponse]:
    """Get all teams with their current Elo ratings."""
    logger.info("Getting all teams")
    
    # Get teams from the provider
    adapter = ProviderRegistry.get_adapter(settings.PROVIDER)
    provider_teams = adapter.get_teams()
    
    # Get Elo model for ratings
    elo_model = get_elo_model()
    elo_model.load_ratings_from_db()
    
    teams_response = []
    for team in provider_teams:
        # Get Elo rating from database
        db_team = db.query(Team).filter(
            Team.abbreviation == team.abbreviation
        ).first()
        
        elo_rating = None
        if db_team:
            elo_rating = elo_model.ratings.get(db_team.id, 1500.0)
        
        teams_response.append(TeamResponse(
            abbreviation=team.abbreviation,
            name=team.name,
            city=team.city,
            conference=team.conference,
            division=team.division,
            elo_rating=elo_rating
        ))
    
    logger.info(f"Returning {len(teams_response)} teams")
    return teams_response