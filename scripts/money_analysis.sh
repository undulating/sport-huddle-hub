docker exec nflpred-api python -c "$(cat << 'EOF'
#!/usr/bin/env python3
"""
Analyze potential betting returns based on model predictions and moneyline odds.
This script simulates different accuracy scenarios to understand potential returns.

IMPORTANT: This is for analytical/educational purposes only. 
Please gamble responsibly if you choose to use this information.
"""

import sys
sys.path.append('/app')

from api.storage.db import get_db_context
from api.storage.models import Game, Team
from api.models.elo_model import EloModel
from datetime import datetime
import pandas as pd
import numpy as np

def calculate_payout(bet_amount, american_odds):
    """Calculate payout for American odds."""
    if american_odds > 0:
        # Positive odds: amount won per $100 bet
        return bet_amount * (1 + american_odds / 100)
    else:
        # Negative odds: amount to bet to win $100
        return bet_amount * (1 + 100 / abs(american_odds))

def analyze_betting_performance(season=2025, weeks=None, bet_amount=1000):
    """
    Analyze betting performance based on model predictions.
    
    Args:
        season: NFL season to analyze
        weeks: List of weeks to analyze (None for all)
        bet_amount: Amount to bet on each game
    """
    
    # Initialize Elo model
    elo_model = EloModel()
    elo_model.load_ratings_from_db()
    
    with get_db_context() as db:
        # Query games with moneyline odds
        query = db.query(Game).filter(
            Game.season == season,
            Game.home_moneyline.isnot(None),
            Game.away_moneyline.isnot(None)
        )
        
        if weeks:
            query = query.filter(Game.week.in_(weeks))
        
        games = query.order_by(Game.week, Game.game_date).all()
        
        if not games:
            print(f"No games found with moneyline odds for season {season}")
            return
        
        # Analyze each game
        results = []
        
        for game in games:
            # Get team info
            home_team = db.query(Team).filter(Team.id == game.home_team_id).first()
            away_team = db.query(Team).filter(Team.id == game.away_team_id).first()
            
            # Get model prediction
            pred = elo_model.predict_game(game.home_team_id, game.away_team_id)
            
            # Determine which team the model favors
            model_pick_home = pred['home_win_probability'] > pred['away_win_probability']
            confidence = max(pred['home_win_probability'], pred['away_win_probability'])
            
            # Calculate potential payout
            if model_pick_home:
                odds = game.home_moneyline
                team_picked = home_team.abbreviation
                opponent = away_team.abbreviation
            else:
                odds = game.away_moneyline
                team_picked = away_team.abbreviation
                opponent = home_team.abbreviation
            
            potential_payout = calculate_payout(bet_amount, odds)
            potential_profit = potential_payout - bet_amount
            
            # Determine actual winner (if game is completed)
            actual_winner = None
            if game.home_score is not None and game.away_score is not None:
                actual_winner_home = game.home_score > game.away_score
                actual_winner = home_team.abbreviation if actual_winner_home else away_team.abbreviation
                model_correct = (model_pick_home == actual_winner_home)
            else:
                model_correct = None
            
            results.append({
                'week': game.week,
                'game': f"{away_team.abbreviation} @ {home_team.abbreviation}",
                'model_pick': team_picked,
                'confidence': confidence,
                'odds': int(odds),
                'bet': bet_amount,
                'potential_payout': round(potential_payout, 2),
                'potential_profit': round(potential_profit, 2),
                'actual_winner': actual_winner,
                'correct': model_correct
            })
        
        # Convert to DataFrame for analysis
        df = pd.DataFrame(results)
        
        print("\n" + "="*80)
        print(f"BETTING ANALYSIS: Season {season}, ${bet_amount} per bet")
        print("="*80)
        
        # Show summary statistics
        print(f"\nTotal games analyzed: {len(df)}")
        completed_games = df[df['correct'].notna()]
        if len(completed_games) > 0:
            actual_accuracy = completed_games['correct'].mean()
            print(f"Actual model accuracy: {actual_accuracy:.1%} ({completed_games['correct'].sum()}/{len(completed_games)})")
        
        # Display all picks
        print("\n" + "-"*80)
        print("ALL MODEL PICKS:")
        print("-"*80)
        
        for _, row in df.iterrows():
            result_symbol = ""
            if row['correct'] is not None:
                result_symbol = " ✅" if row['correct'] else " ❌"
            
            print(f"Week {row['week']:2d}: {row['game']:15s} | Pick: {row['model_pick']:3s} "
                  f"({row['confidence']*100:4.1f}%) | Odds: {row['odds']:+4d} | "
                  f"Profit: ${row['potential_profit']:6.2f}{result_symbol}")
        
        # Simulate different accuracy scenarios
        print("\n" + "-"*80)
        print("RETURN ANALYSIS BY ACCURACY LEVEL:")
        print("-"*80)
        print("\nSimulating returns at different model accuracy levels:")
        print(f"(Assuming ${bet_amount} bet on each game)")
        print()
        
        # Sort by confidence for selective betting
        df_sorted = df.sort_values('confidence', ascending=False).reset_index(drop=True)
        
        accuracy_levels = [0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
        
        print(f"{'Accuracy':<10} | {'Total Bet':<10} | {'Total Return':<12} | {'Net Profit':<12} | {'ROI':<8}")
        print("-" * 65)
        
        for accuracy in accuracy_levels:
            # Simulate wins based on accuracy
            # Higher confidence games more likely to win
            np.random.seed(42)  # For reproducibility
            
            # Create win probability based on confidence and target accuracy
            win_probs = df_sorted['confidence'].values
            # Adjust probabilities to achieve target accuracy
            adjustment = accuracy / win_probs.mean()
            adjusted_probs = np.clip(win_probs * adjustment, 0, 1)
            
            # Simulate outcomes
            wins = np.random.random(len(df_sorted)) < adjusted_probs
            
            total_bet = len(df_sorted) * bet_amount
            total_return = sum(df_sorted.loc[wins, 'potential_payout'])
            net_profit = total_return - total_bet
            roi = (net_profit / total_bet) * 100
            
            print(f"{accuracy:8.0%} | ${total_bet:9.2f} | ${total_return:11.2f} | "
                  f"${net_profit:+11.2f} | {roi:+7.1f}%")
        
        # Confidence-based betting strategy
        print("\n" + "-"*80)
        print("CONFIDENCE-BASED BETTING STRATEGY:")
        print("-"*80)
        print("\nReturns if only betting on high-confidence games:")
        print()
        
        confidence_thresholds = [0.55, 0.60, 0.65, 0.70, 0.75]
        
        print(f"{'Min Conf':<10} | {'Games':<6} | {'Avg Odds':<9} | {'Breakeven%':<11} | {'@50% Acc':<12} | {'@75% Acc':<12} | {'@90% Acc':<12}")
        print("-" * 95)
        
        for threshold in confidence_thresholds:
            high_conf = df_sorted[df_sorted['confidence'] >= threshold]
            if len(high_conf) > 0:
                avg_odds = high_conf['odds'].mean()
                avg_payout_ratio = high_conf['potential_payout'].mean() / bet_amount
                breakeven_pct = 1 / avg_payout_ratio
                
                # Calculate returns at different accuracy levels
                games_count = len(high_conf)
                total_bet = games_count * bet_amount
                
                # 50% accuracy
                wins_50 = int(games_count * 0.5)
                return_50 = wins_50 * (high_conf['potential_payout'].mean())
                profit_50 = return_50 - total_bet
                
                # 75% accuracy
                wins_75 = int(games_count * 0.75)
                return_75 = wins_75 * (high_conf['potential_payout'].mean())
                profit_75 = return_75 - total_bet
                
                # 90% accuracy
                wins_90 = int(games_count * 0.9)
                return_90 = wins_90 * (high_conf['potential_payout'].mean())
                profit_90 = return_90 - total_bet
                
                print(f"{threshold:8.0%} | {games_count:6d} | {avg_odds:+8.0f} | {breakeven_pct:10.1%} | ${profit_50:+11.0f} | ${profit_75:+11.0f} | ${profit_90:+11.0f}")
        
        # Week-by-week performance
        if len(completed_games) > 0:
            print("\n" + "-"*80)
            print("ACTUAL PERFORMANCE BY WEEK:")
            print("-"*80)
            print()
            
            week_summary = []
            for week in completed_games['week'].unique():
                week_games = completed_games[completed_games['week'] == week]
                week_correct = week_games['correct'].sum()
                week_total = len(week_games)
                week_accuracy = week_games['correct'].mean()
                
                # Calculate actual returns
                week_wins = week_games[week_games['correct'] == True]
                week_return = week_wins['potential_payout'].sum()
                week_bet = len(week_games) * bet_amount
                week_profit = week_return - week_bet
                
                week_summary.append({
                    'Week': week,
                    'Record': f"{week_correct}-{week_total-week_correct}",
                    'Accuracy': f"{week_accuracy:.1%}",
                    'Bet': f"${week_bet:.0f}",
                    'Return': f"${week_return:.2f}",
                    'Profit': f"${week_profit:+.2f}",
                    'ROI': f"{(week_profit/week_bet)*100:+.1f}%"
                })
            
            week_df = pd.DataFrame(week_summary)
            print(week_df.to_string(index=False))
            
            # Overall actual performance
            total_correct = completed_games['correct'].sum()
            total_games = len(completed_games)
            total_wins = completed_games[completed_games['correct'] == True]
            total_return = total_wins['potential_payout'].sum()
            total_bet = total_games * bet_amount
            total_profit = total_return - total_bet
            
            print("\n" + "="*80)
            print("OVERALL ACTUAL PERFORMANCE:")
            print(f"Record: {total_correct}-{total_games-total_correct} ({total_correct/total_games:.1%})")
            print(f"Total Bet: ${total_bet:.2f}")
            print(f"Total Return: ${total_return:.2f}")
            print(f"Net Profit: ${total_profit:+.2f}")
            print(f"ROI: {(total_profit/total_bet)*100:+.1f}%")
            print("="*80)

# Run the analysis
if __name__ == "__main__":
    print("\n🏈 NFL BETTING PERFORMANCE ANALYZER 🏈")
    print("Based on Elo Model Predictions vs Actual Moneyline Odds")
    
    # Analyze 2025 season weeks with completed games
    # Adjust these parameters as needed
    analyze_betting_performance(
        season=2025,
        weeks=[1, 2, 3],  # Specify weeks or None for all
        bet_amount=100
    )
    
    print("\n⚠️  DISCLAIMER: This analysis is for educational purposes only.")
    print("Please gamble responsibly and never bet more than you can afford to lose.")
    print("Past performance does not guarantee future results.")
EOF )"