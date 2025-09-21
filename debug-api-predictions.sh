#!/bin/bash
# debug-api-predictions.sh - Find why predictions aren't returning

echo "====================================="
echo "🔍 DEBUGGING PREDICTIONS API"
echo "====================================="
echo ""

# Step 1: Check if the API is running
echo "1. Checking if API is running..."
curl -s http://localhost:8000/health/ping | python3 -m json.tool || echo "❌ API not responding"

# Step 2: Check if we have games in the database
echo ""
echo "2. Checking database for games..."
docker exec nflpred-api python3 -c "
import sys
sys.path.append('/app')
from api.storage.db import get_db_context
from api.storage.models import Game, Team

with get_db_context() as db:
    # Check 2025 Week 3 games
    games = db.query(Game).filter(
        Game.season == 2025,
        Game.week == 3
    ).all()
    
    print(f'Found {len(games)} games for 2025 Week 3')
    
    if games:
        for g in games[:3]:  # Show first 3
            home = db.query(Team).filter(Team.id == g.home_team_id).first()
            away = db.query(Team).filter(Team.id == g.away_team_id).first()
            print(f'  {away.abbreviation if away else \"?\"} @ {home.abbreviation if home else \"?\"} on {g.game_date}')
    
    # Check if we have any 2025 games at all
    total_2025 = db.query(Game).filter(Game.season == 2025).count()
    print(f'\\nTotal 2025 games in database: {total_2025}')
    
    # Check team Elo ratings
    teams_with_elo = db.query(Team).filter(Team.elo_rating.isnot(None)).count()
    print(f'Teams with Elo ratings: {teams_with_elo}/32')
"

# Step 3: Test the EloModel directly
echo ""
echo "3. Testing EloModel directly..."
docker exec nflpred-api python3 -c "
import sys
sys.path.append('/app')
from api.models.elo_model import EloModel
from api.models.elo_recent_form import EloRecentFormModel

print('Testing Standard Elo Model:')
try:
    elo = EloModel()
    elo.load_ratings_from_db()
    print(f'  Loaded {len(elo.ratings)} team ratings')
    
    # Test a prediction
    if len(elo.ratings) > 0:
        teams = list(elo.ratings.keys())[:2]
        pred = elo.predict_game(teams[0], teams[1])
        print(f'  Test prediction works: {pred[\"home_win_probability\"]:.2%}')
    else:
        print('  ❌ No ratings loaded!')
except Exception as e:
    print(f'  ❌ Error: {e}')
    import traceback
    traceback.print_exc()

print('\\nTesting Elo Recent Form Model:')
try:
    elo_recent = EloRecentFormModel()
    elo_recent.load_ratings_from_db()
    print(f'  Loaded {len(elo_recent.ratings)} team ratings')
    
    if len(elo_recent.ratings) > 0:
        teams = list(elo_recent.ratings.keys())[:2]
        pred = elo_recent.predict_game(teams[0], teams[1])
        print(f'  Test prediction works: {pred[\"home_win_probability\"]:.2%}')
except Exception as e:
    print(f'  ❌ Error: {e}')
    import traceback
    traceback.print_exc()
"

# Step 4: Test the predictions route directly
echo ""
echo "4. Testing predictions route directly in Python..."
docker exec nflpred-api python3 -c "
import sys
sys.path.append('/app')

# Enable all logging
import logging
logging.basicConfig(level=logging.DEBUG)

from api.routes.predictions import get_predictions
from api.storage.db import get_db_context
import asyncio

async def test_predictions():
    with get_db_context() as db:
        try:
            # Call the function directly
            result = await get_predictions(
                season=2025,
                week=3,
                model='elo',
                db=db
            )
            print(f'\\n✅ Direct call returned {len(result)} predictions')
            if result:
                print(f'Example: {result[0].away_team} @ {result[0].home_team}')
                print(f'Model: {result[0].model_used}')
        except Exception as e:
            print(f'❌ Error calling get_predictions: {e}')
            import traceback
            traceback.print_exc()

# Run the async function
asyncio.run(test_predictions())
"

# Step 5: Check the actual HTTP endpoint
echo ""
echo "5. Testing HTTP endpoint with verbose output..."
curl -v "http://localhost:8000/api/predictions?season=2025&week=3&model=elo" 2>&1 | grep -E "< HTTP|< content-length|^{|^\[" || echo "No response"

# Step 6: Check if the route is registered
echo ""
echo "6. Checking if predictions route is registered..."
curl -s http://localhost:8000/openapi.json | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    paths = data.get('paths', {})
    if '/api/predictions' in paths:
        print('✅ /api/predictions route is registered')
        methods = list(paths['/api/predictions'].keys())
        print(f'   Methods: {methods}')
    else:
        print('❌ /api/predictions route NOT found!')
        print('Available paths:', list(paths.keys())[:10])
except Exception as e:
    print(f'Error checking routes: {e}')
"

# Step 7: Check for import errors
echo ""
echo "7. Checking for import errors in predictions.py..."
docker exec nflpred-api python3 -c "
import sys
sys.path.append('/app')

try:
    from api.routes import predictions
    print('✅ predictions module imports successfully')
    
    # Check if router exists
    if hasattr(predictions, 'router'):
        print('✅ router exists in predictions module')
    else:
        print('❌ No router in predictions module!')
        
except ImportError as e:
    print(f'❌ Import error: {e}')
    import traceback
    traceback.print_exc()
"

# Step 8: Check app.py to see if route is included
echo ""
echo "8. Checking if predictions router is included in app.py..."
docker exec nflpred-api grep -n "predictions" /app/api/app.py || echo "❌ predictions not found in app.py"

echo ""
echo "====================================="
echo "📋 DIAGNOSIS SUMMARY"
echo "====================================="
echo ""
echo "Check the output above for ❌ marks to identify the issue."
echo "Most likely problems:"
echo "1. No games in database for 2025 Week 3"
echo "2. Elo ratings not loaded"
echo "3. Route not registered in app.py"
echo "4. Import error in predictions.py"