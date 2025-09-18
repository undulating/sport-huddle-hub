"""Prediction API endpoints."""
from typing import List, Optional
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from api.deps import get_db
from api.storage.models import Game, Team, ModelVersion
from api.models.elo_model import EloModel
from sqlalchemy.orm import Session

router = APIRouter()

class GamePrediction(BaseModel):
    game_id: int
    home_team: str
    away_team: str
    home_win_probability: float
    away_win_probability: float
    predicted_spread: float
    confidence: float
    game_time: datetime

@router.get("/current-week", response_model=List[GamePrediction])
async def get_current_week_predictions(db: Session = Depends(get_db)):
    """Get predictions for the current NFL week."""
    # For now, let's show Week 1 of 2024 as example
    season = 2024
    week = 1
    
    # Load the trained model
    elo = EloModel()
    elo.train_on_historical_data(2015, 2024)
    
    # Get games for this week
    games = db.query(Game).filter(
        Game.season == season,
        Game.week == week
    ).all()
    
    predictions = []
    for game in games:
        # Get team abbreviations
        home_team = db.query(Team).filter(Team.id == game.home_team_id).first()
        away_team = db.query(Team).filter(Team.id == game.away_team_id).first()
        
        # Get prediction
        pred = elo.predict_game(game.home_team_id, game.away_team_id)
        
        predictions.append(GamePrediction(
            game_id=game.id,
            home_team=home_team.abbreviation,
            away_team=away_team.abbreviation,
            home_win_probability=pred['home_win_probability'],
            away_win_probability=pred['away_win_probability'],
            predicted_spread=pred['predicted_spread'],
            confidence=pred['confidence'],
            game_time=game.game_date
        ))
    
    return predictions

@router.get("/teams")
async def get_team_ratings(db: Session = Depends(get_db)):
    """Get all teams with their current Elo ratings."""
    teams = db.query(Team).filter(
        Team.elo_rating.isnot(None)
    ).order_by(Team.elo_rating.desc()).all()
    
    return [
        {
            "abbreviation": team.abbreviation,
            "name": team.name,
            "city": team.city,
            "elo_rating": round(team.elo_rating),
            "conference": team.conference,
            "division": team.division
        }
        for team in teams
    ]