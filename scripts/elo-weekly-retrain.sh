#!/bin/bash
# elo-weekly-retrain.sh - Run this every Tuesday for full weekly retrain

echo "📅 WEEKLY ELO RETRAIN (Run on Tuesdays)"
echo "========================================"
echo ""

CURRENT_YEAR=$(date +%Y)
BACKUP_DIR="./elo_backups/weekly"
mkdir -p $BACKUP_DIR

# Backup first
echo "1. Creating weekly backup..."
./retrain-elo.sh | head -20

# Full retrain with all completed games
echo ""
echo "2. Full retrain with all data..."
docker exec nflpred-api python -c "
import sys
sys.path.append('/app')
from api.models.elo_model import EloModel
from api.storage.db import get_db_context
from api.storage.models import Team

elo = EloModel()
print('Training on 2015-$CURRENT_YEAR...')
elo.train_on_historical_data(2015, $CURRENT_YEAR)

# Show current week performance
from api.storage.models import Game
from datetime import datetime, timedelta

with get_db_context() as db:
    # Find current week games
    recent_date = datetime.utcnow() - timedelta(days=7)
    recent_games = db.query(Game).filter(
        Game.game_date >= recent_date,
        Game.home_score.isnot(None)
    ).all()
    
    if recent_games:
        correct = 0
        for game in recent_games:
            pred = elo.predict_game(game.home_team_id, game.away_team_id)
            if (pred['home_win_probability'] > 0.5) == (game.home_score > game.away_score):
                correct += 1
        
        print(f'\\nThis week: {correct}/{len(recent_games)} correct ({correct/len(recent_games)*100:.1f}%)')
    
    # Save ratings
    teams = db.query(Team).all()
    for team in teams:
        if team.id in elo.ratings:
            team.elo_rating = elo.ratings[team.id]
    db.commit()
    
print('✅ Weekly retrain complete!')
"