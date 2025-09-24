#!/bin/bash

# check-stored-predictions-fixed.sh
# Fixed version - properly handles SQL result rows

set -e

echo "=========================================="
echo "🎯 CHECKING STORED PREDICTIONS VS ACTUALS"
echo "=========================================="
echo ""

echo "Checking 2025 Weeks 1-2 (predictions table may not exist)..."
docker exec nflpred-api python3 -c "
import sys
sys.path.insert(0, '/app')
from sqlalchemy.orm import sessionmaker
from api.storage.db import engine
from api.storage.models import Game, Team
from sqlalchemy import text
import pandas as pd

Session = sessionmaker(bind=engine)
session = Session()

print('📊 2025 Season - Results Check')
print('=' * 60)

# First, just check the games and actual results
query = text('''
    SELECT 
        g.week,
        at.abbreviation as away_team,
        ht.abbreviation as home_team,
        g.away_score,
        g.home_score,
        CASE 
            WHEN g.home_score > g.away_score THEN ht.abbreviation
            ELSE at.abbreviation
        END as actual_winner,
        ht.elo_rating as home_elo,
        at.elo_rating as away_elo
    FROM games g
    JOIN teams ht ON g.home_team_id = ht.id
    JOIN teams at ON g.away_team_id = at.id
    WHERE g.season = 2025 
        AND g.week IN (1, 2)
        AND g.home_score IS NOT NULL
        AND g.away_score IS NOT NULL
    ORDER BY g.week, g.game_date
''')

# Use pandas to handle the results cleanly
with engine.connect() as conn:
    df = pd.read_sql(query, conn)

if df.empty:
    print('No completed games found for 2025 Weeks 1-2')
else:
    print(f'Found {len(df)} games')
    print('')
    
    # Check what the frontend would show (using home advantage)
    HOME_ADVANTAGE = 57  # Standard Elo home advantage
    
    correct_predictions = 0
    total_games = 0
    
    for week in [1, 2]:
        week_df = df[df['week'] == week]
        if not week_df.empty:
            print(f'📅 Week {week}:')
            print('-' * 40)
            
            week_correct = 0
            for _, game in week_df.iterrows():
                total_games += 1
                
                # Calculate what the model would predict (with home advantage)
                home_elo_adjusted = game['home_elo'] + HOME_ADVANTAGE
                away_elo_adjusted = game['away_elo']
                
                # Standard Elo probability formula
                home_win_prob = 1 / (1 + 10 ** ((away_elo_adjusted - home_elo_adjusted) / 400))
                away_win_prob = 1 - home_win_prob
                
                # Predicted winner
                predicted_winner = game['home_team'] if home_win_prob > 0.5 else game['away_team']
                
                # Check if correct
                is_correct = predicted_winner == game['actual_winner']
                if is_correct:
                    correct_predictions += 1
                    week_correct += 1
                
                icon = '✅' if is_correct else '❌'
                
                print(f'{icon} {game[\"away_team\"]:3} @ {game[\"home_team\"]:3}: ', end='')
                print(f'{game[\"away_score\"]}-{game[\"home_score\"]} ', end='')
                print(f'(Predicted: {predicted_winner} {max(home_win_prob, away_win_prob):.1%}, ', end='')
                print(f'Won: {game[\"actual_winner\"]})')
                
                # Special check for KC @ LAC
                if game['away_team'] == 'KC' and game['home_team'] == 'LAC':
                    print(f'    → LAC home advantage: +{HOME_ADVANTAGE} Elo points')
                    print(f'    → Effective ratings: LAC {home_elo_adjusted:.0f} vs KC {away_elo_adjusted:.0f}')
            
            if len(week_df) > 0:
                week_acc = (week_correct / len(week_df) * 100)
                print(f'\\nWeek {week} Accuracy: {week_correct}/{len(week_df)} ({week_acc:.1f}%)')
    
    print('\\n' + '=' * 60)
    print('📊 OVERALL PERFORMANCE:')
    print(f'Total Record: {correct_predictions}-{total_games - correct_predictions}')
    overall_acc = (correct_predictions / total_games * 100) if total_games > 0 else 0
    print(f'Overall Accuracy: {overall_acc:.1f}%')
    print(f'\\nYour reported: 28-5 (84.8%)')
    
    if correct_predictions == 28 and total_games == 33:
        print('✨ Numbers match perfectly!')

# Specific KC @ LAC game analysis
print('\\n🔍 Detailed Analysis: KC @ LAC Week 1')
print('=' * 60)

kc = session.query(Team).filter(Team.abbreviation == 'KC').first()
lac = session.query(Team).filter(Team.abbreviation == 'LAC').first()

game = session.query(Game).filter(
    Game.season == 2025,
    Game.week == 1,
    Game.home_team_id == lac.id,
    Game.away_team_id == kc.id
).first()

if game:
    print(f'Game Setup: KC (away) @ LAC (home)')
    print(f'Actual Score: KC {game.away_score} - LAC {game.home_score}')
    print(f'Actual Winner: {\"LAC\" if game.home_score > game.away_score else \"KC\"}')
    print(f'')
    print(f'Elo Ratings (from database):')
    print(f'  KC:  {kc.elo_rating:.1f}')
    print(f'  LAC: {lac.elo_rating:.1f}')
    print(f'')
    print(f'With Home Advantage (+57):')
    print(f'  KC (away):  {kc.elo_rating:.1f}')
    print(f'  LAC (home): {lac.elo_rating + 57:.1f} (effective)')
    print(f'')
    
    # Calculate prediction
    home_elo_adj = lac.elo_rating + 57
    away_elo = kc.elo_rating
    home_prob = 1 / (1 + 10 ** ((away_elo - home_elo_adj) / 400))
    
    print(f'Model Prediction:')
    print(f'  LAC win probability: {home_prob:.1%}')
    print(f'  KC win probability: {(1-home_prob):.1%}')
    print(f'  Predicted winner: {\"LAC\" if home_prob > 0.5 else \"KC\"}')
    print(f'')
    
    if home_prob > 0.5 and game.home_score > game.away_score:
        print('✅ MODEL CORRECTLY PREDICTED LAC!')
    elif home_prob < 0.5 and game.away_score > game.home_score:
        print('✅ MODEL CORRECTLY PREDICTED KC!')
    else:
        print('❌ Model prediction was incorrect')
"