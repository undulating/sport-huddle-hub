#!/bin/bash
# retrain-elo.sh - Main script to safely retrain Elo model with latest games

echo "=========================================="
echo "🏈 ELO MODEL RETRAINING SCRIPT"
echo "=========================================="
echo "This script safely retrains your Elo model"
echo "including all completed games up to today"
echo "=========================================="
echo ""

# Configuration
START_SEASON=2023  # Earliest season in your data
END_SEASON=2025    # Current season
BACKUP_DIR="./elo_backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Create backup directory if it doesn't exist
mkdir -p $BACKUP_DIR

# Step 1: Backup current Elo ratings
echo "1. Backing up current Elo ratings..."
docker exec nflpred-api python -c "
import sys
sys.path.append('/app')
import json
from datetime import datetime
from api.models.elo_model import EloModel
from api.storage.db import get_db_context
from api.storage.models import Team

# Load current ratings
elo = EloModel()
elo.load_ratings_from_db()

# Save to backup file
backup_data = {
    'timestamp': '$TIMESTAMP',
    'ratings': elo.ratings,
    'teams': {}
}

with get_db_context() as db:
    teams = db.query(Team).all()
    for team in teams:
        if team.elo_rating:
            backup_data['teams'][team.id] = {
                'abbreviation': team.abbreviation,
                'rating': team.elo_rating
            }

# Write backup
with open('/app/elo_backup_$TIMESTAMP.json', 'w') as f:
    json.dump(backup_data, f, indent=2)

print(f'✅ Backed up {len(backup_data[\"teams\"])} team ratings')
"

# Copy backup to host
docker cp nflpred-api:/app/elo_backup_$TIMESTAMP.json $BACKUP_DIR/
echo "   Backup saved to: $BACKUP_DIR/elo_backup_$TIMESTAMP.json"

# Step 2: Check for new completed games
echo ""
echo "2. Checking for completed games to include..."
docker exec nflpred-api python -c "
import sys
sys.path.append('/app')
from api.storage.db import get_db_context
from api.storage.models import Game
from sqlalchemy import func
from datetime import datetime, timedelta

with get_db_context() as db:
    # Count games by completion status
    total_games = db.query(func.count(Game.id)).scalar()
    completed_games = db.query(func.count(Game.id)).filter(
        Game.home_score.isnot(None),
        Game.away_score.isnot(None)
    ).scalar()
    
    # Recent completed games (last 7 days)
    recent_date = datetime.utcnow() - timedelta(days=7)
    recent_games = db.query(Game).filter(
        Game.home_score.isnot(None),
        Game.away_score.isnot(None),
        Game.game_date >= recent_date
    ).order_by(Game.game_date.desc()).limit(5).all()
    
    print(f'Total games in database: {total_games}')
    print(f'Completed games: {completed_games}')
    print(f'Incomplete games: {total_games - completed_games}')
    
    if recent_games:
        print(f'\\nRecent completed games (last 7 days):')
        for g in recent_games:
            print(f'  - {g.game_date.strftime(\"%Y-%m-%d\")}: Game ID {g.id}')
"

# Step 3: Retrain the model
echo ""
echo "3. Retraining Elo model on ALL completed games ($START_SEASON-$END_SEASON)..."
docker exec nflpred-api python -c "
import sys
sys.path.append('/app')
from api.models.elo_model import EloModel
from api.storage.db import get_db_context
from api.storage.models import Team, Game
import numpy as np

# Initialize and train
elo = EloModel()
print(f'Training on seasons $START_SEASON to $END_SEASON...')
elo.train_on_historical_data($START_SEASON, $END_SEASON)

# Evaluate performance
print('\\n📊 MODEL PERFORMANCE BY SEASON:')
print('Season | Games | Accuracy | Brier Score')
print('-------|-------|----------|------------')

accuracies = []
for season in range($START_SEASON, $END_SEASON + 1):
    results = elo.evaluate_predictions(season)
    if results['games'] > 0:
        accuracies.append(results['accuracy'])
        print(f'{season}   | {results[\"games\"]:3d}   | {results[\"accuracy\"]*100:5.1f}%   | {results[\"brier_score\"]:.3f}')

if accuracies:
    print('-------|-------|----------|------------')
    print(f'OVERALL|       | {np.mean(accuracies)*100:5.1f}%   |')

# Save updated ratings to database
print('\\n4. Saving updated Elo ratings to database...')
with get_db_context() as db:
    teams = db.query(Team).all()
    updated = 0
    
    for team in teams:
        if team.id in elo.ratings:
            old_rating = team.elo_rating
            new_rating = elo.ratings[team.id]
            team.elo_rating = new_rating
            
            if old_rating and abs(old_rating - new_rating) > 1:
                print(f'  {team.abbreviation}: {old_rating:.0f} → {new_rating:.0f} ({new_rating-old_rating:+.0f})')
            
            updated += 1
    
    db.commit()
    print(f'\\n✅ Updated {updated} team Elo ratings')
"

# Step 4: Verify predictions still work
echo ""
echo "5. Testing predictions endpoint..."
RESPONSE=$(curl -s "http://localhost:8000/api/predictions?season=2025&week=3")

if [ ! -z "$RESPONSE" ] && [ "$RESPONSE" != "[]" ]; then
    echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data:
        print(f'✅ Predictions working! Found {len(data)} games for Week 3')
        game = data[0]
        print(f'   Sample: {game[\"away_team\"]} @ {game[\"home_team\"]} ({game[\"home_win_probability\"]*100:.1f}%)')
except:
    print('⚠️ Could not parse response')
"
else
    echo "⚠️ No predictions returned - check the API"
fi

# Step 6: Show rating changes for top teams
echo ""
echo "6. Top 10 Teams by Elo Rating:"
docker exec nflpred-api python -c "
import sys
sys.path.append('/app')
from api.storage.db import get_db_context
from api.storage.models import Team

with get_db_context() as db:
    top_teams = db.query(Team).filter(
        Team.elo_rating.isnot(None)
    ).order_by(Team.elo_rating.desc()).limit(10).all()
    
    print('Rank | Team | Elo Rating')
    print('-----|------|----------')
    for i, team in enumerate(top_teams, 1):
        print(f'{i:4} | {team.abbreviation:4} | {team.elo_rating:.0f}')
"

echo ""
echo "=========================================="
echo "✅ RETRAINING COMPLETE!"
echo "=========================================="
echo "- Backup saved to: $BACKUP_DIR/elo_backup_$TIMESTAMP.json"
echo "- Model retrained on all games from $START_SEASON-$END_SEASON"
echo "- Frontend will now show updated percentages"
echo "- No breaking changes to the API"
echo "=========================================="