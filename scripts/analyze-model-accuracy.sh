#!/bin/bash

# analyze-model-accuracy-fixed.sh
# Fixed version - handles predict_game return values correctly

set -e

echo "=========================================="
echo "🎯 MODEL ACCURACY ANALYZER - 2025 SEASON"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "1. Checking 2025 Week 1 predictions vs actuals..."
echo "================================================"
docker exec nflpred-api python3 -c "
import sys
sys.path.insert(0, '/app')
from sqlalchemy.orm import sessionmaker
from api.storage.db import engine
from api.storage.models import Game, Team
from api.models.elo_model import EloModel
from datetime import datetime
import pandas as pd

Session = sessionmaker(bind=engine)
session = Session()

# Initialize Elo model
elo_model = EloModel()
elo_model.load_ratings_from_db()

def analyze_week(season, week):
    print(f'\n📅 Week {week}, {season} Analysis')
    print('=' * 60)
    
    # Get all games for the week
    games = session.query(Game).filter(
        Game.season == season,
        Game.week == week
    ).all()
    
    if not games:
        print(f'No games found for Week {week}')
        return None
    
    results = []
    correct_picks = 0
    total_games = 0
    
    for game in games:
        # Skip games that haven't been played
        if game.home_score is None or game.away_score is None:
            continue
            
        total_games += 1
        
        # Get team names
        home_team = session.query(Team).filter(Team.id == game.home_team_id).first()
        away_team = session.query(Team).filter(Team.id == game.away_team_id).first()
        
        if not home_team or not away_team:
            continue
        
        # Get Elo predictions - handle different return formats
        try:
            prediction_result = elo_model.predict_game(game.home_team_id, game.away_team_id)
            
            # Handle different return formats
            if isinstance(prediction_result, dict):
                home_prob = prediction_result.get('home_win_probability', 0.5)
                away_prob = prediction_result.get('away_win_probability', 0.5)
            elif isinstance(prediction_result, tuple) and len(prediction_result) >= 2:
                home_prob = prediction_result[0]
                away_prob = prediction_result[1]
            else:
                # Try to unpack whatever we got
                home_prob = 0.5
                away_prob = 0.5
                print(f'  Warning: Unexpected prediction format for {away_team.abbreviation} @ {home_team.abbreviation}')
        except Exception as e:
            print(f'  Error getting prediction for {away_team.abbreviation} @ {home_team.abbreviation}: {e}')
            home_prob = 0.5
            away_prob = 0.5
        
        # Determine predicted winner
        predicted_winner = home_team.abbreviation if home_prob > 0.5 else away_team.abbreviation
        predicted_prob = max(home_prob, away_prob)
        
        # Determine actual winner
        actual_winner = home_team.abbreviation if game.home_score > game.away_score else away_team.abbreviation
        
        # Check if prediction was correct
        is_correct = predicted_winner == actual_winner
        if is_correct:
            correct_picks += 1
        
        # Calculate confidence and upset status
        confidence = abs(home_prob - 0.5) * 2  # 0 = tossup, 1 = very confident
        is_upset = (home_prob > 0.5 and game.home_score < game.away_score) or \
                   (away_prob > 0.5 and game.home_score > game.away_score)
        
        result = {
            'away': away_team.abbreviation,
            'home': home_team.abbreviation,
            'away_score': game.away_score,
            'home_score': game.home_score,
            'predicted_winner': predicted_winner,
            'actual_winner': actual_winner,
            'predicted_prob': predicted_prob,
            'confidence': confidence,
            'correct': is_correct,
            'upset': is_upset,
            'margin': abs(game.home_score - game.away_score)
        }
        results.append(result)
        
        # Print game result
        status_icon = '✅' if is_correct else '❌'
        upset_flag = '🔥 UPSET!' if is_upset else ''
        
        print(f'{status_icon} {away_team.abbreviation:3} @ {home_team.abbreviation:3} | ', end='')
        print(f'Score: {game.away_score:2}-{game.home_score:2} | ', end='')
        print(f'Picked: {predicted_winner:3} ({predicted_prob:.1%}) | ', end='')
        print(f'Winner: {actual_winner:3} {upset_flag}')
    
    if total_games > 0:
        accuracy = (correct_picks / total_games) * 100
        print(f'\n📊 Week {week} Summary:')
        print(f'  Correct: {correct_picks}/{total_games} ({accuracy:.1f}%)')
        
        # Analyze by confidence level
        df = pd.DataFrame(results)
        if not df.empty:
            # High confidence games (>65% probability)
            high_conf = df[df['predicted_prob'] > 0.65]
            if len(high_conf) > 0:
                high_conf_acc = (high_conf['correct'].sum() / len(high_conf)) * 100
                print(f'  High Confidence (>65%): {high_conf[\"correct\"].sum()}/{len(high_conf)} ({high_conf_acc:.1f}%)')
            
            # Low confidence games (50-65% probability)
            low_conf = df[(df['predicted_prob'] >= 0.5) & (df['predicted_prob'] <= 0.65)]
            if len(low_conf) > 0:
                low_conf_acc = (low_conf['correct'].sum() / len(low_conf)) * 100
                print(f'  Low Confidence (50-65%): {low_conf[\"correct\"].sum()}/{len(low_conf)} ({low_conf_acc:.1f}%)')
            
            # Upset analysis
            upsets = df[df['upset'] == True]
            print(f'  Upsets: {len(upsets)} games')
            
            # Close games analysis (margin <= 7)
            close_games = df[df['margin'] <= 7]
            if len(close_games) > 0:
                close_acc = (close_games['correct'].sum() / len(close_games)) * 100
                print(f'  Close Games (≤7 pts): {close_games[\"correct\"].sum()}/{len(close_games)} ({close_acc:.1f}%)')
            
            # Blowout games (margin > 14)
            blowouts = df[df['margin'] > 14]
            if len(blowouts) > 0:
                blowout_acc = (blowouts['correct'].sum() / len(blowouts)) * 100
                print(f'  Blowouts (>14 pts): {blowouts[\"correct\"].sum()}/{len(blowouts)} ({blowout_acc:.1f}%)')
        
        return accuracy, correct_picks, total_games, results
    
    return None

# Analyze Week 1
week1_results = analyze_week(2025, 1)

# Analyze Week 2  
week2_results = analyze_week(2025, 2)

# Overall summary
print('\n' + '=' * 60)
print('🏆 2025 SEASON SUMMARY (Weeks 1-2)')
print('=' * 60)

total_correct = 0
total_games = 0

if week1_results:
    total_correct += week1_results[1]
    total_games += week1_results[2]

if week2_results:
    total_correct += week2_results[1]
    total_games += week2_results[2]

if total_games > 0:
    overall_accuracy = (total_correct / total_games) * 100
    print(f'Overall Record: {total_correct}-{total_games - total_correct}')
    print(f'Overall Accuracy: {overall_accuracy:.1f}%')
    print(f'Games Analyzed: {total_games}')
    
    # Compare to baseline
    baseline = 50.0  # Random chance
    vs_baseline = overall_accuracy - baseline
    print(f'vs Random Chance: {vs_baseline:+.1f}%')
    
    # Historical comparison
    historical_elo = 62.5  # Your historical Elo accuracy
    vs_historical = overall_accuracy - historical_elo
    print(f'vs Historical Elo: {vs_historical:+.1f}%')
"

echo ""
echo "2. Quick check of predict_game method format..."
echo "==============================================="
docker exec nflpred-api python3 -c "
import sys
sys.path.insert(0, '/app')
from api.models.elo_model import EloModel

# Test what predict_game actually returns
elo = EloModel()
elo.load_ratings_from_db()

# Test with a sample game
result = elo.predict_game(1, 2)  # Sample team IDs

print('predict_game returns:')
print(f'  Type: {type(result)}')
print(f'  Value: {result}')

if isinstance(result, dict):
    print('  Format: Dictionary')
    print(f'  Keys: {list(result.keys())}')
elif isinstance(result, tuple):
    print(f'  Format: Tuple with {len(result)} elements')
else:
    print(f'  Format: {type(result).__name__}')
"

echo ""
echo "3. Alternative: Direct database query for results..."
echo "===================================================="
docker exec nflpred-api python3 -c "
import sys
sys.path.insert(0, '/app')
from sqlalchemy import text
from api.storage.db import engine
import pandas as pd

# Direct SQL query for cleaner results
query = '''
    SELECT 
        g.week,
        g.season,
        ht.abbreviation as home_team,
        at.abbreviation as away_team,
        g.home_score,
        g.away_score,
        CASE 
            WHEN g.home_score > g.away_score THEN ht.abbreviation
            ELSE at.abbreviation
        END as actual_winner,
        ht.elo_rating as home_elo,
        at.elo_rating as away_elo,
        CASE
            WHEN ht.elo_rating > at.elo_rating THEN ht.abbreviation
            ELSE at.abbreviation
        END as elo_predicted_winner,
        CASE
            WHEN (ht.elo_rating > at.elo_rating AND g.home_score > g.away_score) OR
                 (at.elo_rating > ht.elo_rating AND g.away_score > g.home_score)
            THEN 1 ELSE 0
        END as prediction_correct
    FROM games g
    JOIN teams ht ON g.home_team_id = ht.id
    JOIN teams at ON g.away_team_id = at.id
    WHERE g.season = 2025 
        AND g.week IN (1, 2)
        AND g.home_score IS NOT NULL
        AND g.away_score IS NOT NULL
    ORDER BY g.week, g.game_date
'''

with engine.connect() as conn:
    df = pd.read_sql(query, conn)

if not df.empty:
    print('🏈 2025 Season Results (Weeks 1-2)')
    print('=' * 60)
    
    for week in [1, 2]:
        week_df = df[df['week'] == week]
        if not week_df.empty:
            print(f'\n📅 Week {week}:')
            correct = week_df['prediction_correct'].sum()
            total = len(week_df)
            acc = (correct / total * 100) if total > 0 else 0
            
            print(f'Record: {correct}-{total - correct} ({acc:.1f}%)')
            
            for _, game in week_df.iterrows():
                icon = '✅' if game['prediction_correct'] else '❌'
                print(f'{icon} {game[\"away_team\"]:3} @ {game[\"home_team\"]:3}: ', end='')
                print(f'{game[\"away_score\"]}-{game[\"home_score\"]} ', end='')
                print(f'(Picked: {game[\"elo_predicted_winner\"]}, Won: {game[\"actual_winner\"]})')
    
    # Overall stats
    print('\n' + '=' * 60)
    print('📊 OVERALL STATS:')
    total_correct = df['prediction_correct'].sum()
    total_games = len(df)
    overall_acc = (total_correct / total_games * 100) if total_games > 0 else 0
    
    print(f'Total Record: {total_correct}-{total_games - total_correct}')
    print(f'Overall Accuracy: {overall_acc:.1f}%')
    
else:
    print('No games found for 2025 Weeks 1-2')
"

echo ""
echo "=========================================="
echo "✨ ANALYSIS COMPLETE!"
echo "=========================================="