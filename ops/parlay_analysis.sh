#!/bin/bash
# parlay_analyzer.sh
# Analyzes optimal parlay combinations based on model confidence intervals
# Save this in ops/ directory and run with: bash parlay_analyzer.sh

cat << 'PYTHON_SCRIPT' | docker exec -i nflpred-api python -
import sys
sys.path.append('/app')

from api.storage.db import get_db_context
from api.storage.models import Game, Team
from api.models.elo_model import EloModel
from itertools import combinations
import pandas as pd
import numpy as np
from datetime import datetime

def calculate_parlay_payout(bet_amount, odds_list):
    """Calculate parlay payout for multiple American odds."""
    multiplier = 1.0
    for odds in odds_list:
        if odds > 0:
            multiplier *= (1 + odds / 100)
        else:
            multiplier *= (1 + 100 / abs(odds))
    return bet_amount * multiplier

def calculate_parlay_probability(probabilities):
    """Calculate combined probability for parlay."""
    return np.prod(probabilities)

def analyze_parlay_opportunities(season=2025, week=None, bet_amount=10):
    """
    Analyze optimal parlay combinations based on confidence intervals.
    """
    
    elo_model = EloModel()
    elo_model.load_ratings_from_db()
    
    with get_db_context() as db:
        # Query upcoming games
        query = db.query(Game).filter(
            Game.season == season,
            Game.home_moneyline.isnot(None),
            Game.away_moneyline.isnot(None),
            Game.home_score.is_(None)  # Only unplayed games
        )
        
        if week:
            query = query.filter(Game.week == week)
        else:
            # Get next week's games
            query = query.order_by(Game.week).limit(16)
        
        games = query.all()
        
        if not games:
            print("No upcoming games found with moneyline odds")
            return
        
        # Analyze each game
        game_data = []
        
        for game in games:
            home_team = db.query(Team).filter(Team.id == game.home_team_id).first()
            away_team = db.query(Team).filter(Team.id == game.away_team_id).first()
            
            pred = elo_model.predict_game(game.home_team_id, game.away_team_id)
            
            # Determine model pick
            if pred['home_win_probability'] > pred['away_win_probability']:
                pick = home_team.abbreviation
                confidence = pred['home_win_probability']
                odds = game.home_moneyline
                matchup = f"{away_team.abbreviation}@{home_team.abbreviation}"
            else:
                pick = away_team.abbreviation
                confidence = pred['away_win_probability']
                odds = game.away_moneyline
                matchup = f"{away_team.abbreviation}@{home_team.abbreviation}"
            
            # Calculate expected value
            if odds > 0:
                implied_prob = 100 / (odds + 100)
            else:
                implied_prob = abs(odds) / (abs(odds) + 100)
            
            edge = confidence - implied_prob
            
            game_data.append({
                'week': game.week,
                'matchup': matchup,
                'pick': pick,
                'confidence': confidence,
                'odds': odds,
                'implied_prob': implied_prob,
                'edge': edge,
                'game_date': game.game_date
            })
        
        df = pd.DataFrame(game_data)
        
        print("\n" + "="*80)
        print(f"PARLAY ANALYSIS: Season {season}, Week {week if week else 'Next'}")
        print("="*80)
        
        # High Confidence Picks
        print("\n" + "-"*80)
        print("HIGH CONFIDENCE PICKS (>70%):")
        print("-"*80)
        
        high_conf = df[df['confidence'] > 0.70].sort_values('confidence', ascending=False)
        
        for _, row in high_conf.iterrows():
            print(f"W{int(row['week']):2d}: {row['matchup']:15s} | Pick: {row['pick']:3s} "
                  f"({row['confidence']*100:4.1f}%) | Odds: {row['odds']:+4d} | "
                  f"Edge: {row['edge']*100:+5.1f}%")
        
        # Best 2-Team Parlays
        print("\n" + "-"*80)
        print("OPTIMAL 2-TEAM PARLAYS:")
        print("-"*80)
        
        # Focus on games with positive edge and high confidence
        good_picks = df[(df['edge'] > 0.05) & (df['confidence'] > 0.60)]
        
        if len(good_picks) >= 2:
            parlay_2team = []
            
            for combo in combinations(good_picks.index, 2):
                games_combo = good_picks.loc[list(combo)]
                
                combined_prob = calculate_parlay_probability(games_combo['confidence'].values)
                parlay_odds = calculate_parlay_payout(1, games_combo['odds'].values)
                expected_value = (combined_prob * parlay_odds) - 1
                
                parlay_2team.append({
                    'games': ' + '.join(games_combo['pick'].values),
                    'matchups': ' | '.join(games_combo['matchup'].values),
                    'probability': combined_prob,
                    'payout': parlay_odds,
                    'ev': expected_value,
                    'odds_list': games_combo['odds'].tolist()
                })
            
            best_2team = sorted(parlay_2team, key=lambda x: x['ev'], reverse=True)[:5]
            
            print(f"\nTop 5 by Expected Value (${bet_amount} bet):")
            print(f"{'Parlay':<20} | {'Win %':<8} | {'Payout':<10} | {'EV':<8}")
            print("-" * 55)
            
            for parlay in best_2team:
                win_pct = parlay['probability'] * 100
                payout = parlay['payout'] * bet_amount
                ev = parlay['ev'] * bet_amount
                
                print(f"{parlay['games']:<20} | {win_pct:6.1f}% | ${payout:8.2f} | ${ev:+6.2f}")
        
        # Best 3-Team Parlays
        print("\n" + "-"*80)
        print("OPTIMAL 3-TEAM PARLAYS:")
        print("-"*80)
        
        if len(good_picks) >= 3:
            parlay_3team = []
            
            for combo in combinations(good_picks.index, 3):
                games_combo = good_picks.loc[list(combo)]
                
                combined_prob = calculate_parlay_probability(games_combo['confidence'].values)
                parlay_odds = calculate_parlay_payout(1, games_combo['odds'].values)
                expected_value = (combined_prob * parlay_odds) - 1
                
                parlay_3team.append({
                    'games': ' + '.join(games_combo['pick'].values),
                    'probability': combined_prob,
                    'payout': parlay_odds,
                    'ev': expected_value
                })
            
            best_3team = sorted(parlay_3team, key=lambda x: x['ev'], reverse=True)[:5]
            
            print(f"\nTop 5 by Expected Value (${bet_amount} bet):")
            print(f"{'Parlay':<30} | {'Win %':<8} | {'Payout':<10} | {'EV':<8}")
            print("-" * 65)
            
            for parlay in best_3team[:5]:
                win_pct = parlay['probability'] * 100
                payout = parlay['payout'] * bet_amount
                ev = parlay['ev'] * bet_amount
                
                # Truncate team names if too long
                teams = parlay['games']
                if len(teams) > 30:
                    teams = teams[:27] + "..."
                
                print(f"{teams:<30} | {win_pct:6.1f}% | ${payout:8.2f} | ${ev:+6.2f}")
        
        # Conservative Parlays (high probability)
        print("\n" + "-"*80)
        print("CONSERVATIVE PARLAYS (Highest Win Probability):")
        print("-"*80)
        
        # Find parlays with highest combined probability
        very_high_conf = df[df['confidence'] > 0.75]
        
        if len(very_high_conf) >= 2:
            safe_parlays = []
            
            for size in [2, 3]:
                if len(very_high_conf) >= size:
                    for combo in combinations(very_high_conf.index, size):
                        games_combo = very_high_conf.loc[list(combo)]
                        
                        combined_prob = calculate_parlay_probability(games_combo['confidence'].values)
                        parlay_odds = calculate_parlay_payout(1, games_combo['odds'].values)
                        
                        safe_parlays.append({
                            'games': ' + '.join(games_combo['pick'].values),
                            'size': size,
                            'probability': combined_prob,
                            'payout': parlay_odds
                        })
            
            safe_sorted = sorted(safe_parlays, key=lambda x: x['probability'], reverse=True)[:5]
            
            print(f"\nSafest Parlays (${bet_amount} bet):")
            print(f"{'Parlay':<30} | {'Legs':<5} | {'Win %':<8} | {'Payout':<10}")
            print("-" * 60)
            
            for parlay in safe_sorted:
                win_pct = parlay['probability'] * 100
                payout = parlay['payout'] * bet_amount
                
                teams = parlay['games']
                if len(teams) > 30:
                    teams = teams[:27] + "..."
                
                print(f"{teams:<30} | {parlay['size']:^5d} | {win_pct:6.1f}% | ${payout:8.2f}")
        
        # Round Robin Analysis
        print("\n" + "-"*80)
        print("ROUND ROBIN ANALYSIS (Top 4 Picks):")
        print("-"*80)
        
        top4 = good_picks.nlargest(4, 'confidence')
        
        if len(top4) == 4:
            print(f"\nBase Picks: {', '.join(top4['pick'].values)}")
            print(f"Individual Confidences: {', '.join([f'{c:.1%}' for c in top4['confidence'].values])}")
            
            # Calculate all 2-team parlays from top 4
            rr_2team_results = []
            for combo in combinations(range(4), 2):
                subset = top4.iloc[list(combo)]
                prob = calculate_parlay_probability(subset['confidence'].values)
                payout = calculate_parlay_payout(bet_amount, subset['odds'].values)
                rr_2team_results.append((prob, payout))
            
            # Calculate expected return
            total_bet = len(rr_2team_results) * bet_amount
            expected_return = sum(prob * payout for prob, payout in rr_2team_results)
            
            print(f"\n2-Team Round Robin (6 parlays × ${bet_amount}):")
            print(f"  Total Bet: ${total_bet:.2f}")
            print(f"  Expected Return: ${expected_return:.2f}")
            print(f"  Expected Profit: ${expected_return - total_bet:+.2f}")
            print(f"  ROI: {((expected_return - total_bet) / total_bet * 100):+.1f}%")
        
        # Correlation Warning
        print("\n" + "="*80)
        print("⚠️  IMPORTANT CONSIDERATIONS:")
        print("-"*40)
        print("• Parlays multiply risk exponentially")
        print("• A 70% win probability on each leg = 49% for 2-team, 34% for 3-team")
        print("• Divisional games may have correlated outcomes")
        print("• Always consider your bankroll management strategy")
        print("• The house edge increases with each leg added")
        print("="*80)

if __name__ == "__main__":
    print("\n🏈 PARLAY COMBINATION ANALYZER 🏈")
    print("Finding Optimal Parlays Based on Model Confidence")
    
    # Analyze next week's games
    # Change week=None to week=4 for a specific week
    analyze_parlay_opportunities(
        season=2025,
        week=3,  # Set to None for next available games
        bet_amount=10
    )
    
    print("\n⚠️  DISCLAIMER: This analysis is for educational purposes only.")
    print("Parlays are high-risk, high-reward bets with negative expected value.")
    print("Please gamble responsibly.")

PYTHON_SCRIPT