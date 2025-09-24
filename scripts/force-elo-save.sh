#!/bin/bash
# force-elo-save.sh - Force save Elo ratings using direct SQL updates

echo "💪 FORCE SAVING ELO RATINGS"
echo "==========================="
echo ""

# Method 1: Direct SQL UPDATE
echo "Using direct SQL updates to force save..."
docker exec nflpred-api python -c "
import sys
sys.path.append('/app')
from api.models.elo_model import EloModel
from api.storage.db import get_db_context
from api.storage.models import Team
from sqlalchemy import text

# Train the model
elo = EloModel()
print('Training Elo model...')
elo.train_on_historical_data(2023, 2025)
print(f'Trained with {len(elo.ratings)} ratings')

# Force update using raw SQL
with get_db_context() as db:
    updated = 0
    for team_id, rating in elo.ratings.items():
        # Use raw SQL to force the update
        result = db.execute(
            text('UPDATE teams SET elo_rating = :rating WHERE id = :team_id'),
            {'rating': float(rating), 'team_id': team_id}
        )
        if result.rowcount > 0:
            updated += 1
    
    db.commit()
    print(f'✅ Force updated {updated} teams with SQL')
    
    # Verify the updates
    print('\\nVerifying updates:')
    result = db.execute(
        text('SELECT abbreviation, elo_rating FROM teams WHERE elo_rating IS NOT NULL ORDER BY elo_rating DESC LIMIT 10')
    )
    for row in result:
        print(f'  {row[0]}: {row[1]:.0f}')
"

echo ""
echo "Testing both models..."
echo ""

# Test Pure Elo
echo "Pure Elo (should show real percentages):"
curl -s "http://localhost:8000/api/predictions?season=2024&week=1&model=elo" 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data and len(data) > 0:
        game = data[0]
        prob = game['home_win_probability']
        if prob != 0.5:
            print(f'  ✅ {game[\"home_team\"]} vs {game[\"away_team\"]}: {prob*100:.1f}%')
        else:
            print('  ❌ Still showing 50/50')
            print('  Restarting API...')
except:
    print('  ⚠️ No response - restarting API')
" || echo "  Need to restart API"

# Test Recent Form
echo ""
echo "Recent Form (with adjustments):"
curl -s "http://localhost:8000/api/predictions?season=2024&week=1&model=elo_recent" 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data and len(data) > 0:
        game = data[0]
        prob = game['home_win_probability']
        print(f'  ✅ {game[\"home_team\"]} vs {game[\"away_team\"]}: {prob*100:.1f}%')
except:
    print('  ⚠️ No response')
" || echo "  API issue"

echo ""
echo "If Pure Elo still shows 50/50:"
echo "  docker compose restart api"
echo "  sleep 5"
echo "  curl 'http://localhost:8000/api/predictions?season=2024&week=1&model=elo' | jq '.[:2]'"