#!/bin/bash

# diagnose-prediction-discrepancy.sh
# Figure out why frontend shows different predictions than analysis

set -e

echo "=========================================="
echo "🔍 DIAGNOSING PREDICTION DISCREPANCY"
echo "=========================================="
echo ""

echo "1. Checking the actual KC vs LAC game in Week 1..."
echo "=================================================="
docker exec nflpred-api python3 -c "
import sys
sys.path.insert(0, '/app')
from sqlalchemy.orm import sessionmaker
from api.storage.db import engine
from api.storage.models import Game, Team
from sqlalchemy import and_

Session = sessionmaker(bind=engine)
session = Session()

# Find the KC vs LAC game
kc = session.query(Team).filter(Team.abbreviation == 'KC').first()
lac = session.query(Team).filter(Team.abbreviation == 'LAC').first()

print(f'KC ID: {kc.id}, Current Elo: {kc.elo_rating}')
print(f'LAC ID: {lac.id}, Current Elo: {lac.elo_rating}')

# Find their Week 1 game
game = session.query(Game).filter(
    Game.season == 2025,
    Game.week == 1,
    ((Game.home_team_id == kc.id) | (Game.away_team_id == kc.id)),
    ((Game.home_team_id == lac.id) | (Game.away_team_id == lac.id))
).first()

if game:
    home_team = session.query(Team).filter(Team.id == game.home_team_id).first()
    away_team = session.query(Team).filter(Team.id == game.away_team_id).first()
    
    print(f'\n📅 Week 1 Game Found:')
    print(f'  {away_team.abbreviation} @ {home_team.abbreviation}')
    print(f'  Score: {game.away_score} - {game.home_score}')
    print(f'  Home Team ID: {game.home_team_id}')
    print(f'  Away Team ID: {game.away_team_id}')
"

echo ""
echo "2. Testing BOTH Elo models (Standard and Recent Form)..."
echo "========================================================"
docker exec nflpred-api python3 -c "
import sys
sys.path.insert(0, '/app')
from sqlalchemy.orm import sessionmaker
from api.storage.db import engine
from api.storage.models import Game, Team
from api.models.elo_model import EloModel
try:
    from api.models.elo_recent_form import EloRecentFormModel
    has_recent = True
except:
    has_recent = False

Session = sessionmaker(bind=engine)
session = Session()

# Get the teams
kc = session.query(Team).filter(Team.abbreviation == 'KC').first()
lac = session.query(Team).filter(Team.abbreviation == 'LAC').first()

# Find their game
game = session.query(Game).filter(
    Game.season == 2025,
    Game.week == 1,
    ((Game.home_team_id == kc.id) | (Game.away_team_id == kc.id)),
    ((Game.home_team_id == lac.id) | (Game.away_team_id == lac.id))
).first()

if game:
    print('🏈 KC vs LAC Predictions:')
    print('=' * 50)
    
    # Standard Elo
    elo_standard = EloModel()
    elo_standard.load_ratings_from_db()
    
    # Get prediction
    result = elo_standard.predict_game(game.home_team_id, game.away_team_id)
    
    print(f'\n1. Standard Elo Model:')
    print(f'   predict_game returned type: {type(result)}')
    print(f'   Raw result: {result}')
    
    # Parse the result based on type
    if isinstance(result, dict):
        home_prob = result.get('home_win_probability', 0)
        away_prob = result.get('away_win_probability', 0)
        spread = result.get('predicted_spread', 0)
        print(f'   Home prob: {home_prob:.1%}')
        print(f'   Away prob: {away_prob:.1%}')
        print(f'   Spread: {spread:.1f}')
    elif isinstance(result, tuple):
        if len(result) >= 2:
            print(f'   Element 0: {result[0]}')
            print(f'   Element 1: {result[1]}')
            if len(result) > 2:
                print(f'   Element 2: {result[2]}')
    
    # Try Recent Form if available
    if has_recent:
        print(f'\n2. Recent Form Model:')
        elo_recent = EloRecentFormModel()
        elo_recent.load_ratings_from_db()
        
        result_recent = elo_recent.predict_game(game.home_team_id, game.away_team_id)
        print(f'   predict_game returned type: {type(result_recent)}')
        print(f'   Raw result: {result_recent}')
"

echo ""
echo "3. Checking what the API predictions endpoint returns..."
echo "========================================================"
# Make actual API call like frontend does
curl -s "http://localhost:8000/api/predictions?season=2025&week=1" | python3 -c "
import sys
import json

try:
    data = json.load(sys.stdin)
    
    # Find KC vs LAC game
    for game in data:
        teams = [game.get('home_team'), game.get('away_team')]
        if 'KC' in teams and 'LAC' in teams:
            print('📡 API /predictions endpoint returns:')
            print('=' * 50)
            print(f\"Home Team: {game.get('home_team')}\")
            print(f\"Away Team: {game.get('away_team')}\")
            print(f\"Home Win Probability: {game.get('home_win_probability', 0):.1%}\")
            print(f\"Away Win Probability: {game.get('away_win_probability', 0):.1%}\")
            print(f\"Predicted Spread: {game.get('predicted_spread', 0):.1f}\")
            
            # Determine favorite
            if game.get('home_win_probability', 0) > 0.5:
                favorite = game.get('home_team')
                prob = game.get('home_win_probability', 0)
            else:
                favorite = game.get('away_team')
                prob = game.get('away_win_probability', 0)
            
            print(f\"\nFavorite: {favorite} ({prob:.1%})\")
            break
except Exception as e:
    print(f'Error parsing API response: {e}')
    print('Raw response:')
    sys.stdin.seek(0)
    print(sys.stdin.read()[:500])
"

echo ""
echo "4. Checking the predictions route code..."
echo "=========================================="
docker exec nflpred-api python3 -c "
import sys
sys.path.insert(0, '/app')

# Check which model the predictions route actually uses
print('Checking api/routes/predictions.py...')
print('')

# Import and check
from api.routes.predictions import get_elo_model

model = get_elo_model()
print(f'Model type used in predictions route: {type(model).__name__}')
print(f'Model class: {model.__class__}')

# Check if it's using recent form or standard
if 'recent' in type(model).__name__.lower():
    print('✓ Using RECENT FORM model')
else:
    print('✓ Using STANDARD Elo model')
"

echo ""
echo "5. Comparing stored Elo ratings vs current calculations..."
echo "=========================================================="
docker exec nflpred-api python3 -c "
import sys
sys.path.insert(0, '/app')
from sqlalchemy.orm import sessionmaker
from api.storage.db import engine
from api.storage.models import Team, ModelVersion
from api.models.elo_model import EloModel

Session = sessionmaker(bind=engine)
session = Session()

# Check stored Elo ratings in teams table
kc = session.query(Team).filter(Team.abbreviation == 'KC').first()
lac = session.query(Team).filter(Team.abbreviation == 'LAC').first()

print('📊 Stored Elo Ratings (in teams table):')
print(f'  KC:  {kc.elo_rating}')
print(f'  LAC: {lac.elo_rating}')

# Check current Elo model's ratings
elo = EloModel()
elo.load_ratings_from_db()

print(f'\n📊 Elo Model Ratings (from model):')
print(f'  KC:  {elo.ratings.get(kc.id, 1500)}')
print(f'  LAC: {elo.ratings.get(lac.id, 1500)}')

# Check if there's a mismatch
if kc.elo_rating != elo.ratings.get(kc.id):
    print(f'\n⚠️ MISMATCH: KC database rating ({kc.elo_rating}) != model rating ({elo.ratings.get(kc.id)})')
if lac.elo_rating != elo.ratings.get(lac.id):
    print(f'⚠️ MISMATCH: LAC database rating ({lac.elo_rating}) != model rating ({elo.ratings.get(lac.id)})')

# Check model versions
latest_version = session.query(ModelVersion).filter(
    ModelVersion.model_type == 'elo'
).order_by(ModelVersion.created_at.desc()).first()

if latest_version:
    print(f'\n📅 Latest model version:')
    print(f'  Created: {latest_version.created_at}')
    print(f'  Accuracy: {latest_version.accuracy}')
    print(f'  Games Trained: {latest_version.games_trained}')
"

echo ""
echo "=========================================="
echo "🔍 DIAGNOSIS COMPLETE"
echo "=========================================="
echo ""
echo "Key things to check:"
echo "1. Is the frontend calling the right model?"
echo "2. Are stored Elo ratings matching the model's ratings?"
echo "3. Is the API returning different values than direct model calls?"
echo "4. Has the model been retrained since the frontend last loaded?"
echo ""
echo "The discrepancy is likely due to:"
echo "- Different models being used (Standard vs Recent Form)"
echo "- Stale Elo ratings in database vs model"
echo "- Frontend caching old predictions"
echo "- Home/away team mix-up in the analysis script"