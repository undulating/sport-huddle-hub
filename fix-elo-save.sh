#!/bin/bash
# fix-elo-save.sh - Properly save Pure Elo ratings to database

echo "🔧 FIXING PURE ELO RATINGS"
echo "=========================="
echo ""

# Direct approach - train and save in one transaction
echo "Training and saving Elo ratings..."
docker exec nflpred-api python -c "
import sys
sys.path.append('/app')
from api.models.elo_model import EloModel
from api.storage.db import get_db_context
from api.storage.models import Team
import numpy as np

# Train the model
elo = EloModel()
print('Training on 2023-2025...')
elo.train_on_historical_data(2023, 2025)

print(f'Trained with {len(elo.ratings)} team ratings')

# Save to database WITH explicit updates
with get_db_context() as db:
    teams = db.query(Team).all()
    updated = 0
    
    for team in teams:
        if team.id in elo.ratings:
            new_rating = float(elo.ratings[team.id])  # Ensure it's a float
            old_rating = team.elo_rating if team.elo_rating else 1500
            
            # Force update
            team.elo_rating = new_rating
            
            if abs(old_rating - new_rating) > 1:
                print(f'  {team.abbreviation}: {old_rating:.0f} → {new_rating:.0f}')
                updated += 1
    
    # Explicitly commit
    db.commit()
    print(f'\\n✅ Saved {updated} team ratings to database')
    
    # Verify it saved
    print('\\nVerifying saved ratings:')
    top_teams = db.query(Team).order_by(Team.elo_rating.desc()).limit(5).all()
    for team in top_teams:
        print(f'  {team.abbreviation}: {team.elo_rating:.0f}')
"

echo ""
echo "Testing Pure Elo predictions..."
curl -s "http://localhost:8000/api/predictions?season=2024&week=1&model=elo" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data:
        game = data[0]
        prob = game['home_win_probability']
        if prob != 0.5:
            print(f'✅ Pure Elo FIXED! {game[\"home_team\"]} vs {game[\"away_team\"]} = {prob*100:.1f}%')
        else:
            print('❌ Still showing 50/50 - may need to restart API')
except Exception as e:
    print(f'Error: {e}')
"

echo ""
echo "If still showing 50/50, restart the API:"
echo "  docker compose restart api"
echo ""
echo "Then test again:"
echo "  curl 'http://localhost:8000/api/predictions?season=2024&week=1&model=elo' | jq '.[0]'"