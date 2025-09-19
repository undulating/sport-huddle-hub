#!/bin/bash
# elo-check-status.sh - Check current Elo model status

echo "📊 ELO MODEL STATUS CHECK"
echo "=========================="
echo ""

docker exec nflpred-api python -c "
import sys
sys.path.append('/app')
from api.storage.db import get_db_context
from api.storage.models import Team, Game, ModelVersion
from sqlalchemy import func
from datetime import datetime, timedelta

with get_db_context() as db:
    # Model version info
    model = db.query(ModelVersion).filter(
        ModelVersion.name == 'elo_basic',
        ModelVersion.is_active == True
    ).first()
    
    if model:
        print('MODEL INFO:')
        print(f'  Version: {model.version}')
        print(f'  Last trained: {model.trained_at}')
        print(f'  K-factor: {model.hyperparameters.get(\"k_factor\", 32)}')
        print()
    
    # Games status
    total_games = db.query(func.count(Game.id)).scalar()
    completed = db.query(func.count(Game.id)).filter(
        Game.home_score.isnot(None)
    ).scalar()
    
    print('GAMES DATABASE:')
    print(f'  Total games: {total_games}')
    print(f'  Completed: {completed}')
    print(f'  Pending: {total_games - completed}')
    print()
    
    # Recent games
    week_ago = datetime.utcnow() - timedelta(days=7)
    recent_completed = db.query(func.count(Game.id)).filter(
        Game.home_score.isnot(None),
        Game.game_date >= week_ago
    ).scalar()
    
    print('RECENT ACTIVITY:')
    print(f'  Games completed (last 7 days): {recent_completed}')
    
    # Top teams
    print()
    print('TOP 5 TEAMS BY ELO:')
    top_teams = db.query(Team).order_by(Team.elo_rating.desc()).limit(5).all()
    for i, team in enumerate(top_teams, 1):
        print(f'  {i}. {team.abbreviation}: {team.elo_rating:.0f}')
    
    # Check for teams with no rating
    unrated = db.query(func.count(Team.id)).filter(
        Team.elo_rating.is_(None)
    ).scalar()
    
    if unrated > 0:
        print(f'\\n⚠️  Warning: {unrated} teams have no Elo rating!')
"

echo ""
echo "Testing predictions endpoint..."
WEEK=$(date +%V)
curl -s "http://localhost:8000/api/predictions?season=2025&week=3" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data:
        print(f'✅ Predictions working - {len(data)} games for Week 3')
        avg_conf = sum(max(g['home_win_probability'], g['away_win_probability']) for g in data) / len(data)
        print(f'   Average confidence: {avg_conf*100:.1f}%')
except:
    print('❌ Predictions endpoint error!')
"