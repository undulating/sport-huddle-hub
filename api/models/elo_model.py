import math
import numpy as np
from datetime import datetime
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass

from api.storage.db import get_db_context
from api.storage.models import Team, Game, Prediction, ModelVersion
from api.app_logging import get_logger

logger = get_logger(__name__)


@dataclass
class EloRating:
    """Elo rating for a team at a point in time."""
    team_id: int
    rating: float
    games_played: int
    last_updated: datetime


class EloModel:
    """
    Elo rating system for NFL predictions.
    
    Key parameters:
    - K-factor: How much ratings change after each game (32 for NFL)
    - Home advantage: Points added to home team (65 Elo points = ~2.5 point spread)
    - Mean reversion: Ratings regress to mean (1500) each season
    """
    
    def __init__(
        self,
        k_factor: float = 32.0,
        home_advantage: float = 65.0,
        mean_rating: float = 1500.0,
        reversion_factor: float = 0.25
    ):
        self.k_factor = k_factor
        self.home_advantage = home_advantage
        self.mean_rating = mean_rating
        self.reversion_factor = reversion_factor
        self.ratings: Dict[int, float] = {}
        
    def initialize_ratings(self):
        """Initialize all teams with base rating."""
        with get_db_context() as db:
            teams = db.query(Team).all()
            for team in teams:
                self.ratings[team.id] = self.mean_rating
            logger.info(f"Initialized {len(teams)} teams with rating {self.mean_rating}")
    
    def expected_score(self, rating_a: float, rating_b: float) -> float:
        """
        Calculate expected score for team A vs team B.
        Returns probability of team A winning (0-1).
        """
        return 1 / (1 + 10 ** ((rating_b - rating_a) / 400))
    
    def update_ratings(
        self, 
        home_team_id: int, 
        away_team_id: int,
        home_won: bool,
        margin: int = 0
    ) -> Tuple[float, float]:
        """
        Update Elo ratings after a game.
        
        Args:
            home_team_id: ID of home team
            away_team_id: ID of away team
            home_won: Whether home team won
            margin: Victory margin (for dynamic K-factor)
            
        Returns:
            Tuple of (new_home_rating, new_away_rating)
        """
        # Get current ratings
        home_rating = self.ratings.get(home_team_id, self.mean_rating)
        away_rating = self.ratings.get(away_team_id, self.mean_rating)
        
        # Add home advantage
        home_rating_adj = home_rating + self.home_advantage
        
        # Calculate expected outcomes
        expected_home = self.expected_score(home_rating_adj, away_rating)
        
        # Actual outcome
        actual_home = 1.0 if home_won else 0.0
        
        # Dynamic K-factor based on margin of victory
        k = self.k_factor
        if margin > 0:
            multiplier = math.log(abs(margin) + 1) * 2.2 / k
            k = k * (1 + multiplier)
        
        # Update ratings
        home_change = k * (actual_home - expected_home)
        self.ratings[home_team_id] = home_rating + home_change
        self.ratings[away_team_id] = away_rating - home_change
        
        return self.ratings[home_team_id], self.ratings[away_team_id]
    
    def season_regression(self):
        """
        Regress ratings toward mean at season start.
        This prevents ratings from getting too extreme over time.
        """
        for team_id in self.ratings:
            current = self.ratings[team_id]
            self.ratings[team_id] = (
                current * (1 - self.reversion_factor) + 
                self.mean_rating * self.reversion_factor
            )
    
    def train_on_historical_data(self, start_season: int = 2015, end_season: int = 2023):
        """
        Train Elo ratings on historical game data.
        """
        with get_db_context() as db:
            # Initialize ratings
            self.initialize_ratings()
            
            # Process each season
            for season in range(start_season, end_season + 1):
                logger.info(f"Processing season {season}")
                
                # Apply season regression
                if season > start_season:
                    self.season_regression()
                
                # Get games in chronological order
                games = db.query(Game).filter(
                    Game.season == season,
                    Game.home_score.isnot(None)
                ).order_by(Game.week, Game.game_date).all()
                
                # Update ratings for each game
                for game in games:
                    home_won = game.home_score > game.away_score
                    margin = abs(game.home_score - game.away_score)
                    
                    self.update_ratings(
                        game.home_team_id,
                        game.away_team_id,
                        home_won,
                        margin
                    )
                
                logger.info(f"Season {season}: Processed {len(games)} games")
            
            # Save final ratings to database
            for team_id, rating in self.ratings.items():
                team = db.query(Team).filter(Team.id == team_id).first()
                if team:
                    team.elo_rating = rating
            db.commit()
            
            logger.info("Training complete! Final ratings saved to database.")
    
    def predict_game(
        self, 
        home_team_id: int, 
        away_team_id: int
    ) -> Dict[str, float]:
        """
        Predict outcome of a game.
        
        Returns:
            Dict with probabilities and predicted scores
        """
        home_rating = self.ratings.get(home_team_id, self.mean_rating)
        away_rating = self.ratings.get(away_team_id, self.mean_rating)
        
        # Add home advantage
        home_rating_adj = home_rating + self.home_advantage
        
        # Calculate win probability
        home_win_prob = self.expected_score(home_rating_adj, away_rating)
        
        # Convert Elo difference to predicted spread
        # Roughly: 25 Elo points = 1 point spread
        elo_diff = home_rating_adj - away_rating
        predicted_spread = elo_diff / 25
        
        # Predict scores (based on NFL averages)
        avg_total = 45.6  # From your data
        if predicted_spread < 0:  # Home team expected to lose
            predicted_home_score = (avg_total / 2) + (predicted_spread / 2)
            predicted_away_score = (avg_total / 2) - (predicted_spread / 2)
        else:  # Home team expected to win
            predicted_home_score = (avg_total / 2) + (predicted_spread / 2)
            predicted_away_score = (avg_total / 2) - (predicted_spread / 2)
        
        return {
            'home_win_probability': home_win_prob,
            'away_win_probability': 1 - home_win_prob,
            'predicted_home_score': max(0, predicted_home_score),
            'predicted_away_score': max(0, predicted_away_score),
            'predicted_spread': predicted_spread,
            'home_elo': home_rating,
            'away_elo': away_rating,
            'confidence': abs(home_win_prob - 0.5) * 2  # 0-1 scale
        }
    
    def predict_week(self, season: int, week: int) -> List[Dict]:
        """
        Generate predictions for all games in a week.
        """
        predictions = []
        
        with get_db_context() as db:
            games = db.query(Game).filter(
                Game.season == season,
                Game.week == week
            ).all()
            
            for game in games:
                pred = self.predict_game(game.home_team_id, game.away_team_id)
                pred['game_id'] = game.id
                pred['game_external_id'] = game.external_id
                predictions.append(pred)
                
                logger.info(
                    f"Game {game.external_id}: "
                    f"Home win prob: {pred['home_win_probability']:.2%}, "
                    f"Spread: {pred['predicted_spread']:.1f}"
                )
        
        return predictions
    
    def evaluate_predictions(self, season: int) -> Dict[str, float]:
        """
        Evaluate model performance for a season.
        """
        correct = 0
        total = 0
        brier_score_sum = 0
        
        with get_db_context() as db:
            games = db.query(Game).filter(
                Game.season == season,
                Game.home_score.isnot(None)
            ).all()
            
            for game in games:
                pred = self.predict_game(game.home_team_id, game.away_team_id)
                actual_home_won = game.home_score > game.away_score
                predicted_home_won = pred['home_win_probability'] > 0.5
                
                if actual_home_won == predicted_home_won:
                    correct += 1
                
                # Brier score (lower is better)
                actual = 1 if actual_home_won else 0
                brier = (pred['home_win_probability'] - actual) ** 2
                brier_score_sum += brier
                
                total += 1
        
        return {
            'season': season,
            'games': total,
            'accuracy': correct / total if total > 0 else 0,
            'brier_score': brier_score_sum / total if total > 0 else 0
        }


# Register the model
def register_elo_model():
    """Register the Elo model in the database."""
    with get_db_context() as db:
        # Check if already registered
        existing = db.query(ModelVersion).filter(
            ModelVersion.name == "elo_basic",
            ModelVersion.version == "1.0.0"
        ).first()
        
        if not existing:
            model_version = ModelVersion(
                name="elo_basic",
                version="1.0.0",
                model_type="classification",
                features_used=["elo_rating", "home_advantage"],
                hyperparameters={
                    "k_factor": 32.0,
                    "home_advantage": 65.0,
                    "mean_rating": 1500.0,
                    "reversion_factor": 0.25
                },
                is_active=True,
                is_default=True,
                description="Basic Elo rating model for NFL game predictions",
                trained_at=datetime.utcnow()
            )
            db.add(model_version)
            db.commit()
            logger.info("Registered Elo model version 1.0.0")
            return model_version
        
        return existing