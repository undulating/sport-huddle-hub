"""Elo model with recent form adjustments - weights recent games more heavily."""
import logging
from typing import Dict, Optional, Tuple
from datetime import datetime, timedelta
import numpy as np
from sqlalchemy import and_, or_, func
from sqlalchemy.orm import Session

from api.storage.db import get_db_context
from api.storage.models import Team, Game
from api.models.elo_model import EloModel

logger = logging.getLogger(__name__)


class EloRecentFormModel(EloModel):
    """Elo model that adjusts ratings based on recent form (last 3-5 games)."""
    
    def __init__(self):
        super().__init__()
        self.recent_games_weight = 0.3  # How much recent form affects prediction (30%)
        self.games_to_consider = 3      # Look at last 3 games
        self.momentum_factor = 50       # Max Elo adjustment for hot/cold streaks
        
    def get_model_name(self) -> str:
        """Return model identifier."""
        return "elo_recent_form"
        
    def get_model_description(self) -> str:
        """Return model description."""
        return "Elo ratings adjusted for recent form (last 3 games weighted more heavily)"
    
    def get_team_recent_form(self, team_id: int, before_date: Optional[datetime] = None) -> Dict:
        """Calculate team's recent form based on last N games."""
        with get_db_context() as db:
            # Get team's last N completed games before the given date
            query = db.query(Game).filter(
                or_(Game.home_team_id == team_id, Game.away_team_id == team_id),
                Game.home_score.isnot(None),
                Game.away_score.isnot(None)
            )
            
            if before_date:
                query = query.filter(Game.game_date < before_date)
            
            recent_games = query.order_by(Game.game_date.desc()).limit(self.games_to_consider).all()
            
            if not recent_games:
                return {
                    'form_rating': 0,
                    'win_rate': 0.5,
                    'avg_point_diff': 0,
                    'games_count': 0,
                    'momentum': 'neutral'
                }
            
            wins = 0
            total_point_diff = 0
            form_points = []
            
            for i, game in enumerate(recent_games):
                # Weight recent games more heavily (most recent = highest weight)
                weight = (self.games_to_consider - i) / self.games_to_consider
                
                if game.home_team_id == team_id:
                    won = game.home_score > game.away_score
                    point_diff = game.home_score - game.away_score
                else:
                    won = game.away_score > game.home_score
                    point_diff = game.away_score - game.home_score
                
                wins += won * weight
                total_point_diff += point_diff * weight
                form_points.append(1 if won else -1)
            
            # Calculate weighted win rate
            weighted_games = sum((self.games_to_consider - i) / self.games_to_consider 
                                for i in range(len(recent_games)))
            win_rate = wins / weighted_games if weighted_games > 0 else 0.5
            
            # Calculate momentum (improving, declining, or stable)
            if len(form_points) >= 2:
                if form_points[0] > form_points[-1]:  # Most recent better than oldest
                    momentum = 'hot'
                    momentum_boost = 20
                elif form_points[0] < form_points[-1]:  # Most recent worse than oldest
                    momentum = 'cold' 
                    momentum_boost = -20
                else:
                    momentum = 'neutral'
                    momentum_boost = 0
            else:
                momentum = 'neutral'
                momentum_boost = 0
            
            # Calculate form rating adjustment
            form_rating = (
                (win_rate - 0.5) * 100 +  # Win rate adjustment
                (total_point_diff / len(recent_games)) * 2 +  # Point differential adjustment  
                momentum_boost  # Momentum adjustment
            )
            
            # Cap the adjustment
            form_rating = max(-self.momentum_factor, min(self.momentum_factor, form_rating))
            
            return {
                'form_rating': form_rating,
                'win_rate': win_rate,
                'avg_point_diff': total_point_diff / len(recent_games),
                'games_count': len(recent_games),
                'momentum': momentum
            }
    
    def predict_game(self, home_team_id: int, away_team_id: int,  
                     game_date: Optional[datetime] = None) -> Dict:
        """
        Predict game outcome with recent form adjustments.
        
        Returns:
            Dict with home_win_probability, away_win_probability, predicted_spread,
            and additional form information
        """
        # Get base Elo prediction
        base_prediction = super().predict_game(home_team_id, away_team_id)
        
        # Get recent form for both teams
        home_form = self.get_team_recent_form(home_team_id, before_date=game_date)
        away_form = self.get_team_recent_form(away_team_id, game_date)
        
        # Adjust Elo ratings based on recent form
        home_rating = self.ratings.get(home_team_id, 1500)
        away_rating = self.ratings.get(away_team_id, 1500)
        
        # Apply form adjustments
        home_adjusted = home_rating + (home_form['form_rating'] * self.recent_games_weight)
        away_adjusted = away_rating + (away_form['form_rating'] * self.recent_games_weight)
        
        # Recalculate probabilities with adjusted ratings
        rating_diff = home_adjusted - away_adjusted + self.home_advantage
        home_win_prob = 1 / (1 + 10 ** (-rating_diff / 400))
        away_win_prob = 1 - home_win_prob
        
        # Predicted spread (negative means away team favored)
        predicted_spread = rating_diff / 25  # Roughly 25 Elo points = 1 point spread
        
        return {
            'home_win_probability': home_win_prob,
            'away_win_probability': away_win_prob,
            'predicted_spread': predicted_spread,
            'model_type': 'elo_recent_form',
            'home_form': home_form,
            'away_form': away_form,
            'base_home_prob': base_prediction['home_win_probability'],
            'base_away_prob': base_prediction['away_win_probability'],
            'form_adjustment': {
                'home': home_form['form_rating'] * self.recent_games_weight,
                'away': away_form['form_rating'] * self.recent_games_weight
            }
        }
    
    def get_hot_teams(self, top_n: int = 5) -> list:
        """Get teams with the best recent form."""
        teams_form = []
        
        with get_db_context() as db:
            teams = db.query(Team).all()
            
            for team in teams:
                form = self.get_team_recent_form(team.id)
                if form['games_count'] >= 2:  # Need at least 2 recent games
                    teams_form.append({
                        'team_id': team.id,
                        'team_name': team.abbreviation,
                        'form_rating': form['form_rating'],
                        'momentum': form['momentum'],
                        'recent_record': f"{int(form['win_rate'] * form['games_count'])}-{form['games_count'] - int(form['win_rate'] * form['games_count'])}"
                    })
        
        # Sort by form rating
        teams_form.sort(key=lambda x: x['form_rating'], reverse=True)
        
        return teams_form[:top_n]
    
    def get_cold_teams(self, bottom_n: int = 5) -> list:
        """Get teams with the worst recent form."""
        teams_form = self.get_hot_teams(top_n=100)  # Get all
        teams_form.sort(key=lambda x: x['form_rating'])
        return teams_form[:bottom_n]


# Singleton instance
_elo_recent_form_model: Optional[EloRecentFormModel] = None


def get_elo_recent_form_model() -> EloRecentFormModel:
    """Get or create the Elo Recent Form model instance."""
    global _elo_recent_form_model
    if _elo_recent_form_model is None:
        _elo_recent_form_model = EloRecentFormModel()
        _elo_recent_form_model.load_ratings_from_db()
    return _elo_recent_form_model