#!/bin/bash
# elo-recent-retrain.sh - Retrain Elo Recent Form model separately

echo "=========================================="
echo "🏈 ELO RECENT FORM RETRAINING SCRIPT"
echo "=========================================="
echo "This script retrains the Elo+Recent Form model"
echo "Note: This model uses Pure Elo as base, so run"
echo "elo-retrain.sh first if Pure Elo needs updating"
echo "=========================================="
echo ""

# Configuration
START_SEASON=2023  # Earliest season in your data
END_SEASON=2025    # Current season
BACKUP_DIR="./elo_backups/recent_form"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Create backup directory if it doesn't exist
mkdir -p $BACKUP_DIR

# Step 1: Backup current Elo Recent Form state
echo "1. Backing up current Elo Recent Form state..."
docker exec nflpred-api python -c "
import sys
sys.path.append('/app')
import json
from datetime import datetime
from api.models.elo_recent_form import EloRecentFormModel
from api.storage.db import get_db_context
from api.storage.models import Team

# Load current model
model = EloRecentFormModel()
model.load_ratings_from_db()

# Save state
backup_data = {
    'timestamp': '$TIMESTAMP',
    'model_type': 'elo_recent_form',
    'ratings': model.ratings,
    'recent_games_weight': model.recent_games_weight,
    'games_to_consider': model.games_to_consider,
    'momentum_factor': model.momentum_factor,
    'teams': {}
}

with get_db_context() as db:
    teams = db.query(Team).all()
    for team in teams:
        if team.id in model.ratings:
            # Get recent form for each team
            form = model.get_team_recent_form(team.id)
            backup_data['teams'][team.id] = {
                'abbreviation': team.abbreviation,
                'base_rating': model.ratings.get(team.id, 1500),
                'form_rating': form['form_rating'],
                'momentum': form['momentum'],
                'recent_record': f\"{int(form['win_rate'] * form['games_count'])}-{form['games_count'] - int(form['win_rate'] * form['games_count'])}\"
            }

# Write backup
with open('/app/elo_recent_backup_$TIMESTAMP.json', 'w') as f:
    json.dump(backup_data, f, indent=2)

print(f'✅ Backed up {len(backup_data[\"teams\"])} team states with recent form data')
"

# Copy backup to host
docker cp nflpred-api:/app/elo_recent_backup_$TIMESTAMP.json $BACKUP_DIR/
echo "   Backup saved to: $BACKUP_DIR/elo_recent_backup_$TIMESTAMP.json"

# Step 2: Ensure base Elo model is trained
echo ""
echo "2. Ensuring base Elo model is trained..."
docker exec nflpred-api python -c "
import sys
sys.path.append('/app')
from api.models.elo_model import EloModel
from api.storage.db import get_db_context
from api.storage.models import Team

# Train base Elo first (Recent Form inherits from this)
elo = EloModel()
print('Training base Elo model on $START_SEASON-$END_SEASON...')
elo.train_on_historical_data($START_SEASON, $END_SEASON)

# Save base ratings to database
with get_db_context() as db:
    teams = db.query(Team).all()
    updated = 0
    for team in teams:
        if team.id in elo.ratings:
            team.elo_rating = elo.ratings[team.id]
            updated += 1
    db.commit()
    print(f'✅ Base Elo updated for {updated} teams')
"

# Step 3: Initialize and evaluate Recent Form model
echo ""
echo "3. Initializing Elo Recent Form model..."
docker exec nflpred-api python -c "
import sys
sys.path.append('/app')
from api.models.elo_recent_form import EloRecentFormModel
from api.storage.db import get_db_context
from api.storage.models import Game, Team
import numpy as np

# Initialize Recent Form model (it will load base ratings)
model = EloRecentFormModel()
model.load_ratings_from_db()

print(f'Loaded {len(model.ratings)} team base ratings')
print(f'Recent games weight: {model.recent_games_weight * 100:.0f}%')
print(f'Games considered: {model.games_to_consider}')
print(f'Momentum factor: ±{model.momentum_factor}')
"

# Step 4: Analyze recent form impact
echo ""
echo "4. Analyzing recent form impact on predictions..."
docker exec nflpred-api python -c "
import sys
sys.path.append('/app')
from api.models.elo_model import EloModel
from api.models.elo_recent_form import EloRecentFormModel
from api.storage.db import get_db_context
from api.storage.models import Game, Team

# Load both models
pure_elo = EloModel()
pure_elo.load_ratings_from_db()

recent_form = EloRecentFormModel()
recent_form.load_ratings_from_db()

# Compare predictions for recent games
print('\\n📊 RECENT FORM IMPACT ANALYSIS:')
print('=' * 60)

with get_db_context() as db:
    # Get some recent games to compare
    recent_games = db.query(Game).filter(
        Game.season == 2025,
        Game.week <= 3,
        Game.home_score.isnot(None)
    ).limit(10).all()
    
    if recent_games:
        print('Game | Pure Elo | w/Recent Form | Diff | Actual Winner')
        print('-----|----------|---------------|------|---------------')
        
        correct_pure = 0
        correct_recent = 0
        
        for game in recent_games:
            # Get team names
            home = db.query(Team).filter(Team.id == game.home_team_id).first()
            away = db.query(Team).filter(Team.id == game.away_team_id).first()
            
            # Get predictions from both models
            pure_pred = pure_elo.predict_game(game.home_team_id, game.away_team_id)
            recent_pred = recent_form.predict_game(game.home_team_id, game.away_team_id, game.game_date)
            
            # Check actual result
            home_won = game.home_score > game.away_score
            winner = home.abbreviation if home_won else away.abbreviation
            
            # Check if predictions were correct
            pure_correct = (pure_pred['home_win_probability'] > 0.5) == home_won
            recent_correct = (recent_pred['home_win_probability'] > 0.5) == home_won
            
            if pure_correct: correct_pure += 1
            if recent_correct: correct_recent += 1
            
            # Display
            game_str = f'{away.abbreviation}@{home.abbreviation}'
            pure_prob = pure_pred['home_win_probability'] * 100
            recent_prob = recent_pred['home_win_probability'] * 100
            diff = recent_prob - pure_prob
            
            pure_mark = '✓' if pure_correct else '✗'
            recent_mark = '✓' if recent_correct else '✗'
            
            print(f'{game_str:5} | {pure_prob:4.0f}% {pure_mark} | {recent_prob:4.0f}% {recent_mark} | {diff:+4.0f}% | {winner}')
        
        print('-----|----------|---------------|------|---------------')
        print(f'Accuracy: Pure={correct_pure}/{len(recent_games)} | Recent={correct_recent}/{len(recent_games)}')
"

# Step 5: Show hot and cold teams
echo ""
echo "5. Current hot and cold teams based on recent form..."
docker exec nflpred-api python -c "
import sys
sys.path.append('/app')
from api.models.elo_recent_form import EloRecentFormModel

model = EloRecentFormModel()
model.load_ratings_from_db()

hot_teams = model.get_hot_teams(5)
cold_teams = model.get_cold_teams(5)

print('\\n🔥 HOT TEAMS (best recent form):')
print('Rank | Team | Form Rating | Momentum | Recent')
print('-----|------|-------------|----------|--------')
for i, team in enumerate(hot_teams, 1):
    print(f'{i:4} | {team[\"team_name\"]:4} | {team[\"form_rating\"]:+11.1f} | {team[\"momentum\"]:8} | {team[\"recent_record\"]}')

print('\\n🧊 COLD TEAMS (worst recent form):')  
print('Rank | Team | Form Rating | Momentum | Recent')
print('-----|------|-------------|----------|--------')
for i, team in enumerate(cold_teams, 1):
    print(f'{i:4} | {team[\"team_name\"]:4} | {team[\"form_rating\"]:+11.1f} | {team[\"momentum\"]:8} | {team[\"recent_record\"]}')
"

# Step 6: Test predictions with both models
echo ""
echo "6. Testing prediction endpoints..."

# Test Pure Elo
PURE_RESPONSE=$(curl -s "http://localhost:8000/api/predictions?season=2025&week=3&model=elo" | head -c 100)
if [ ! -z "$PURE_RESPONSE" ]; then
    echo "   ✅ Pure Elo endpoint working"
else
    echo "   ❌ Pure Elo endpoint not responding"
fi

# Test Recent Form
RECENT_RESPONSE=$(curl -s "http://localhost:8000/api/predictions?season=2025&week=3&model=elo_recent" | head -c 100)
if [ ! -z "$RECENT_RESPONSE" ]; then
    echo "   ✅ Recent Form endpoint working"
else
    echo "   ❌ Recent Form endpoint not responding"
fi

echo ""
echo "=========================================="
echo "✅ RECENT FORM MODEL READY!"
echo "=========================================="
echo "- Backup saved to: $BACKUP_DIR/"
echo "- Base Elo trained on $START_SEASON-$END_SEASON"
echo "- Recent Form adjustments active"
echo "- Frontend can now use model=elo_recent"
echo ""
echo "Model Parameters:"
echo "- Recent games weight: 30%"
echo "- Games considered: Last 3"
echo "- Maximum momentum adjustment: ±50 points"
echo "=========================================="