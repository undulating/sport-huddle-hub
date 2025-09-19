#!/usr/bin/env python3
# elo_utilities.py - Python utility scripts for Elo management
# Save this as api/scripts/elo_utilities.py

import sys
sys.path.append('/app')
import json
import argparse
from datetime import datetime, timedelta
from typing import Dict, Optional, Tuple
from api.models.elo_model import EloModel
from api.storage.db import get_db_context
from api.storage.models import Team, Game
from sqlalchemy import func
import numpy as np

class EloManager:
    """Utility class for managing Elo ratings."""
    
    def __init__(self):
        self.elo = EloModel()
        
    def quick_retrain_recent(self, days_back: int = 7):
        """Retrain only including games from the last N days."""
        print(f"\n🔄 Quick Retraining (last {days_back} days)")
        print("=" * 50)
        
        # Load current ratings as starting point
        self.elo.load_ratings_from_db()
        
        with get_db_context() as db:
            # Find recent completed games
            cutoff_date = datetime.utcnow() - timedelta(days=days_back)
            recent_games = db.query(Game).filter(
                Game.home_score.isnot(None),
                Game.away_score.isnot(None),
                Game.game_date >= cutoff_date
            ).order_by(Game.game_date).all()
            
            print(f"Found {len(recent_games)} completed games since {cutoff_date.date()}")
            
            if not recent_games:
                print("No recent games to update. Ratings unchanged.")
                return
            
            # Update ratings based on recent games only
            for game in recent_games:
                home_rating = self.elo.ratings.get(game.home_team_id, 1500)
                away_rating = self.elo.ratings.get(game.away_team_id, 1500)
                
                # Calculate expected probability
                home_expected = 1 / (1 + 10 ** ((away_rating - home_rating - 65) / 400))
                
                # Actual result
                home_won = 1 if game.home_score > game.away_score else 0
                
                # Update ratings
                k_factor = 32
                rating_change = k_factor * (home_won - home_expected)
                
                self.elo.ratings[game.home_team_id] = home_rating + rating_change
                self.elo.ratings[game.away_team_id] = away_rating - rating_change
                
                print(f"  Game {game.id}: Updated ratings (+{rating_change:.1f}/-{rating_change:.1f})")
            
            # Save to database
            self._save_ratings()
            print("✅ Quick retrain complete!")
    
    def retrain_specific_season(self, season: int):
        """Retrain model focusing on a specific season."""
        print(f"\n🎯 Retraining for Season {season}")
        print("=" * 50)
        
        # Start fresh for single season analysis
        self.elo = EloModel()
        self.elo.train_on_historical_data(season, season)
        
        # Evaluate
        results = self.elo.evaluate_predictions(season)
        print(f"Season {season} Performance:")
        print(f"  Games: {results['games']}")
        print(f"  Accuracy: {results['accuracy']*100:.1f}%")
        print(f"  Brier Score: {results['brier_score']:.3f}")
        
        # Save to database
        self._save_ratings()
        print("✅ Season retrain complete!")
    
    def incremental_update(self, game_ids: list):
        """Update ratings for specific completed games only."""
        print(f"\n➕ Incremental Update for {len(game_ids)} games")
        print("=" * 50)
        
        # Load current ratings
        self.elo.load_ratings_from_db()
        
        with get_db_context() as db:
            for game_id in game_ids:
                game = db.query(Game).filter(Game.id == game_id).first()
                if not game or game.home_score is None:
                    print(f"  Game {game_id}: Skipped (not found or incomplete)")
                    continue
                
                # Get current ratings
                home_rating = self.elo.ratings.get(game.home_team_id, 1500)
                away_rating = self.elo.ratings.get(game.away_team_id, 1500)
                
                # Calculate update
                home_expected = 1 / (1 + 10 ** ((away_rating - home_rating - 65) / 400))
                home_won = 1 if game.home_score > game.away_score else 0
                rating_change = 32 * (home_won - home_expected)
                
                # Update
                self.elo.ratings[game.home_team_id] = home_rating + rating_change
                self.elo.ratings[game.away_team_id] = away_rating - rating_change
                
                print(f"  Game {game_id}: ✅ Updated (Δ = {rating_change:+.1f})")
        
        self._save_ratings()
        print("✅ Incremental update complete!")
    
    def rollback_to_backup(self, backup_file: str):
        """Restore ratings from a backup file."""
        print(f"\n⏪ Rolling back to backup: {backup_file}")
        print("=" * 50)
        
        try:
            with open(backup_file, 'r') as f:
                backup_data = json.load(f)
            
            # Restore ratings
            self.elo.ratings = backup_data['ratings']
            
            # Convert string keys to integers if needed
            self.elo.ratings = {int(k): v for k, v in self.elo.ratings.items()}
            
            # Save to database
            self._save_ratings()
            
            print(f"✅ Restored {len(self.elo.ratings)} team ratings from backup")
            print(f"   Backup timestamp: {backup_data['timestamp']}")
            
        except Exception as e:
            print(f"❌ Error restoring backup: {e}")
    
    def compare_ratings(self, start_season: int = 2020, end_season: int = 2025):
        """Compare current ratings with fresh retrain."""
        print(f"\n📊 Comparing Current vs Fresh Retrain ({start_season}-{end_season})")
        print("=" * 50)
        
        # Load current ratings
        self.elo.load_ratings_from_db()
        current_ratings = self.elo.ratings.copy()
        
        # Fresh retrain
        fresh_elo = EloModel()
        fresh_elo.train_on_historical_data(start_season, end_season)
        
        # Compare
        with get_db_context() as db:
            teams = db.query(Team).all()
            
            print("Team | Current | Fresh | Difference")
            print("-----|---------|-------|------------")
            
            differences = []
            for team in teams:
                if team.id in current_ratings and team.id in fresh_elo.ratings:
                    current = current_ratings[team.id]
                    fresh = fresh_elo.ratings[team.id]
                    diff = fresh - current
                    differences.append(abs(diff))
                    
                    if abs(diff) > 10:  # Only show significant differences
                        print(f"{team.abbreviation:4} | {current:7.0f} | {fresh:5.0f} | {diff:+6.0f}")
            
            print(f"\nAverage difference: {np.mean(differences):.1f}")
            print(f"Max difference: {np.max(differences):.1f}")
    
    def _save_ratings(self):
        """Save current ratings to database."""
        with get_db_context() as db:
            teams = db.query(Team).all()
            updated = 0
            
            for team in teams:
                if team.id in self.elo.ratings:
                    team.elo_rating = self.elo.ratings[team.id]
                    updated += 1
            
            db.commit()
            print(f"💾 Saved {updated} team ratings to database")
    
    def show_weekly_performance(self, season: int, week: int):
        """Show model performance for a specific week."""
        print(f"\n📈 Week {week}, {season} Performance")
        print("=" * 50)
        
        self.elo.load_ratings_from_db()
        
        with get_db_context() as db:
            games = db.query(Game).filter(
                Game.season == season,
                Game.week == week,
                Game.home_score.isnot(None)
            ).all()
            
            correct = 0
            total = 0
            
            print("Away @ Home | Predicted | Actual | Result")
            print("------------|-----------|--------|--------")
            
            for game in games:
                pred = self.elo.predict_game(game.home_team_id, game.away_team_id)
                predicted_home_win = pred['home_win_probability'] > 0.5
                actual_home_win = game.home_score > game.away_score
                
                # Get team names
                home_team = db.query(Team).filter(Team.id == game.home_team_id).first()
                away_team = db.query(Team).filter(Team.id == game.away_team_id).first()
                
                result = "✅" if predicted_home_win == actual_home_win else "❌"
                if predicted_home_win == actual_home_win:
                    correct += 1
                total += 1
                
                pred_str = f"{home_team.abbreviation} ({pred['home_win_probability']*100:.0f}%)"
                actual_str = f"{home_team.abbreviation if actual_home_win else away_team.abbreviation}"
                
                print(f"{away_team.abbreviation:3} @ {home_team.abbreviation:3} | {pred_str:9} | {actual_str:6} | {result}")
            
            if total > 0:
                print(f"\nWeek Accuracy: {correct}/{total} ({correct/total*100:.1f}%)")


# Command-line interface
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Elo Rating Management Utilities')
    parser.add_argument('command', choices=['quick', 'season', 'incremental', 'rollback', 'compare', 'week'],
                       help='Command to execute')
    parser.add_argument('--days', type=int, default=7, help='Days to look back (for quick)')
    parser.add_argument('--season', type=int, default=2025, help='Season to analyze')
    parser.add_argument('--week', type=int, default=1, help='Week to analyze')
    parser.add_argument('--games', type=int, nargs='+', help='Game IDs for incremental update')
    parser.add_argument('--backup', type=str, help='Backup file path for rollback')
    
    args = parser.parse_args()
    manager = EloManager()
    
    if args.command == 'quick':
        manager.quick_retrain_recent(args.days)
    elif args.command == 'season':
        manager.retrain_specific_season(args.season)
    elif args.command == 'incremental':
        if args.games:
            manager.incremental_update(args.games)
        else:
            print("Error: --games required for incremental update")
    elif args.command == 'rollback':
        if args.backup:
            manager.rollback_to_backup(args.backup)
        else:
            print("Error: --backup required for rollback")
    elif args.command == 'compare':
        manager.compare_ratings()
    elif args.command == 'week':
        manager.show_weekly_performance(args.season, args.week)