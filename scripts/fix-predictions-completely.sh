#!/bin/bash
# fix-predictions-completely.sh - Fix all potential issues

echo "====================================="
echo "🛠️ FIXING PREDICTIONS COMPLETELY"
echo "====================================="
echo ""

# Fix 1: Ensure predictions router is registered in app.py
echo "1. Ensuring predictions router is registered..."
docker exec nflpred-api python3 -c "
import sys
sys.path.append('/app')

# Read current app.py
with open('/app/api/app.py', 'r') as f:
    content = f.read()

# Check if predictions is imported
if 'from api.routes import predictions' not in content:
    print('Adding predictions import...')
    # Add import after other route imports
    content = content.replace(
        'from api.routes import health',
        'from api.routes import health, predictions'
    )

# Check if predictions router is included
if 'app.include_router(predictions.router' not in content:
    print('Adding predictions router...')
    # Find where to add it (after health router)
    if 'app.include_router(health.router' in content:
        health_line = 'app.include_router(health.router, prefix=\"/health\", tags=[\"health\"])'
        new_line = health_line + '\\napp.include_router(predictions.router, prefix=\"/api/predictions\", tags=[\"predictions\"])'
        content = content.replace(health_line, new_line)
    else:
        # Add it before the root route
        content = content.replace(
            '@app.get(\"/\")',
            'app.include_router(predictions.router, prefix=\"/api/predictions\", tags=[\"predictions\"])\\n\\n@app.get(\"/\")'
        )

# Save the file
with open('/app/api/app.py', 'w') as f:
    f.write(content)

print('✅ App.py updated with predictions router')
"

# Fix 2: Ensure we have 2025 Week 3 games
echo ""
echo "2. Checking/adding 2025 Week 3 games..."
docker exec nflpred-api python3 -c "
import sys
sys.path.append('/app')
from api.storage.db import get_db_context
from api.storage.models import Game, Team
from datetime import datetime

with get_db_context() as db:
    # Check for 2025 Week 3
    existing = db.query(Game).filter(
        Game.season == 2025,
        Game.week == 3
    ).count()
    
    print(f'Current 2025 Week 3 games: {existing}')
    
    if existing == 0:
        print('No 2025 Week 3 games! Trying to ingest...')
        
        # Try to ingest using the adapter
        from api.adapters import get_adapter
        adapter = get_adapter('nflverse')
        
        games = adapter.get_games(2025, 3)
        print(f'Found {len(games)} games from adapter')
        
        if games:
            # Process and save games
            for game_dto in games[:5]:  # Just first 5 for testing
                home_team = db.query(Team).filter(
                    Team.external_id == game_dto.home_team_external_id
                ).first()
                away_team = db.query(Team).filter(
                    Team.external_id == game_dto.away_team_external_id
                ).first()
                
                if home_team and away_team:
                    new_game = Game(
                        external_id=game_dto.external_id,
                        season=game_dto.season,
                        week=game_dto.week,
                        game_date=game_dto.game_date,
                        kickoff_time=game_dto.kickoff_time,
                        home_team_id=home_team.id,
                        away_team_id=away_team.id,
                        game_status='SCHEDULED'
                    )
                    db.add(new_game)
            
            db.commit()
            print('✅ Added games to database')
    else:
        print(f'✅ Already have {existing} games')
"

# Fix 3: Ensure Elo ratings exist
echo ""
echo "3. Ensuring Elo ratings are loaded..."
docker exec nflpred-api python3 -c "
import sys
sys.path.append('/app')
from api.storage.db import get_db_context
from api.storage.models import Team
from api.models.elo_model import EloModel

with get_db_context() as db:
    # Check current ratings
    teams_with_ratings = db.query(Team).filter(
        Team.elo_rating.isnot(None)
    ).count()
    
    print(f'Teams with Elo ratings: {teams_with_ratings}/32')
    
    if teams_with_ratings < 32:
        print('Loading and saving Elo ratings...')
        
        # Initialize and train model
        elo = EloModel()
        elo.train_on_historical_data(2020, 2024)
        
        # Save to database
        teams = db.query(Team).all()
        for team in teams:
            if team.id in elo.ratings:
                team.elo_rating = elo.ratings[team.id]
        
        db.commit()
        print('✅ Saved Elo ratings to database')
    else:
        print('✅ Elo ratings already loaded')
"

# Fix 4: Fix the predict_game call in predictions.py
echo ""
echo "4. Fixing predict_game signature issue..."
docker exec nflpred-api python3 -c "
import re

# Read the file
with open('/app/api/routes/predictions.py', 'r') as f:
    content = f.read()

# Fix the predict_game call - remove game.game_date parameter
# Look for the pattern and fix it
pattern = r'pred = prediction_model\.predict_game\([^)]+\)'
replacement = '''pred = prediction_model.predict_game(
                game.home_team_id,
                game.away_team_id
            )'''

# Replace the call
content = re.sub(pattern, replacement, content)

# Save the file
with open('/app/api/routes/predictions.py', 'w') as f:
    f.write(content)

print('✅ Fixed predict_game call signature')
"

# Fix 5: Restart the API
echo ""
echo "5. Restarting API to apply all changes..."
docker compose restart api
sleep 5

# Test everything
echo ""
echo "6. Testing predictions endpoint..."
echo ""

for week in 1 2 3; do
    echo "Testing Week $week:"
    RESPONSE=$(curl -s "http://localhost:8000/api/predictions?season=2025&week=$week&model=elo" 2>/dev/null)
    
    if [ -z "$RESPONSE" ]; then
        echo "  ❌ No response for week $week"
    else
        echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, list) and len(data) > 0:
        print(f'  ✅ Week $week: {len(data)} games')
        game = data[0]
        print(f'     {game[\"away_team\"]} @ {game[\"home_team\"]} - {game[\"home_win_probability\"]*100:.1f}%')
    elif isinstance(data, list) and len(data) == 0:
        print('  ⚠️  Week $week: 0 games (might not be scheduled yet)')
    else:
        print(f'  ❌ Week $week: Unexpected response format')
except Exception as e:
    raw = sys.stdin.read()
    if 'detail' in raw:
        print(f'  ❌ Week $week: API Error - {raw}')
    else:
        print(f'  ❌ Week $week: Parse error - {e}')
"
    fi
done

echo ""
echo "====================================="
echo "✅ FIXES APPLIED"
echo "====================================="
echo ""
echo "If predictions are still not working:"
echo "1. Check logs: docker compose logs api --tail=50"
echo "2. Ingest 2025 data: ./scripts/reingest-with-kickoff-times.sh"
echo "3. Rebuild completely: docker compose down && docker compose up --build"