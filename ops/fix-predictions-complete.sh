#!/bin/bash
# fix-predictions-complete.sh - Complete fix for predictions endpoint

echo "==================================="
echo "🔧 FIXING PREDICTIONS ENDPOINT"
echo "==================================="
echo ""

# Step 1: Check the actual error by looking at API logs
echo "1. Checking API logs for errors..."
docker compose logs api --tail=50 | grep -E "(ERROR|WARNING|predictions|Elo)" | tail -10 || echo "No recent errors found"

# Step 2: Test predictions directly in the container
echo ""
echo "2. Testing predictions logic directly..."
docker exec nflpred-api python -c "
import sys
sys.path.append('/app')

from api.storage.db import get_db_context
from api.storage.models import Game, Team
from api.models.elo_model import EloModel
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

print('Testing predictions for 2024 Week 1...')

with get_db_context() as db:
    # Check if we have games
    games = db.query(Game).filter(
        Game.season == 2024,
        Game.week == 1
    ).all()
    
    print(f'Found {len(games)} games for 2024 Week 1')
    
    if games:
        # Initialize and train Elo
        print('Initializing Elo model...')
        elo = EloModel()
        
        print('Training on historical data...')
        elo.train_on_historical_data(2020, 2024)
        
        print(f'Model has {len(elo.ratings)} team ratings')
        
        # Test prediction for first game
        game = games[0]
        home_team = db.query(Team).filter(Team.id == game.home_team_id).first()
        away_team = db.query(Team).filter(Team.id == game.away_team_id).first()
        
        if home_team and away_team:
            pred = elo.predict_game(game.home_team_id, game.away_team_id)
            print(f'\\nSample prediction:')
            print(f'{away_team.abbreviation} @ {home_team.abbreviation}')
            print(f'Home win probability: {pred[\"home_win_probability\"]*100:.1f}%')
            print(f'Predicted spread: {pred[\"predicted_spread\"]:.1f}')
            print('✅ Prediction logic works!')
        else:
            print('❌ Teams not found')
    else:
        print('❌ No games found for 2024 Week 1')
"

# Step 3: Initialize and save Elo ratings to database
echo ""
echo "3. Initializing and saving Elo ratings..."
docker exec nflpred-api python -c "
import sys
sys.path.append('/app')

from api.models.elo_model import EloModel, register_elo_model
from api.storage.db import get_db_context
from api.storage.models import Team

print('Registering Elo model...')
register_elo_model()

print('Training Elo model on all historical data...')
elo = EloModel()
elo.train_on_historical_data(2015, 2024)

print(f'Trained model with {len(elo.ratings)} team ratings')

# Save ratings to database
print('Saving team ratings to database...')
with get_db_context() as db:
    teams = db.query(Team).all()
    updated = 0
    for team in teams:
        if team.id in elo.ratings:
            team.elo_rating = elo.ratings[team.id]
            updated += 1
    db.commit()
    print(f'Updated {updated} team Elo ratings in database')

print('✅ Elo model initialized and saved!')
"

# Step 4: Test the actual API endpoint with curl
echo ""
echo "4. Testing API endpoint after fix..."
sleep 2

# Make direct API call
RESPONSE=$(curl -s -X GET "http://localhost:8000/api/predictions?season=2024&week=1" \
  -H "accept: application/json")

if [ -z "$RESPONSE" ]; then
    echo "❌ Still no response. Checking if endpoint is registered..."
    
    # Check if endpoint exists in API docs
    curl -s http://localhost:8000/openapi.json | python3 -c "
import sys, json
data = json.load(sys.stdin)
if '/api/predictions' in str(data.get('paths', {})):
    print('✅ Predictions endpoint is registered')
else:
    print('❌ Predictions endpoint NOT found in API!')
    print('   The router may not be properly registered')
"
else
    echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, list) and len(data) > 0:
        print(f'✅ SUCCESS! Found {len(data)} predictions')
        game = data[0]
        print(f'Example: {game[\"away_team\"]} @ {game[\"home_team\"]}')
        print(f'Win probability: {game[\"home_win_probability\"]*100:.1f}%')
    elif isinstance(data, dict) and 'error' in data:
        print(f'❌ API Error: {data[\"error\"]}')
    else:
        print('⚠️ Unexpected response format')
        print('Response:', data)
except Exception as e:
    print(f'❌ Parse error: {e}')
    print('Raw response:', sys.stdin.read()[:200])
"
fi

# Step 5: If still not working, restart API
echo ""
echo "5. Restarting API to ensure changes take effect..."
docker compose restart api
sleep 5

# Final test
echo ""
echo "6. Final test after restart..."
FINAL_RESPONSE=$(curl -s "http://localhost:8000/api/predictions?season=2024&week=1")

if [ ! -z "$FINAL_RESPONSE" ]; then
    echo "$FINAL_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data and len(data) > 0:
        print('🎉 FIXED! Predictions endpoint is working!')
        print(f'Returning {len(data)} game predictions')
    else:
        print('⚠️ Endpoint works but returns empty array')
        print('This means no games found for that week')
except:
    print('❌ Still having issues')
"
else
    echo "❌ Still no response after restart"
    echo ""
    echo "Manual debugging needed. Try:"
    echo "1. Check logs: docker compose logs api"
    echo "2. Access API docs: http://localhost:8000/docs"
    echo "3. Look for /api/predictions endpoints"
fi

echo ""
echo "==================================="
echo "TROUBLESHOOTING COMPLETE"
echo "==================================="