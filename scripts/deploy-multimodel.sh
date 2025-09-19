#!/bin/bash
# deploy-multimodel.sh - Deploy the multi-model prediction system

echo "=========================================="
echo "🚀 DEPLOYING MULTI-MODEL SUPPORT"
echo "=========================================="
echo ""

# Step 1: Copy the new model file
echo "1. Installing Elo Recent Form model..."
docker cp api/models/elo_recent_form.py nflpred-api:/app/api/models/
echo "   ✅ Model file copied"

# Step 2: Update the predictions route
echo ""
echo "2. Updating predictions route..."
docker cp api/routes/predictions.py nflpred-api:/app/api/routes/
echo "   ✅ Predictions route updated"

# Step 3: Restart the API to load changes
echo ""
echo "3. Restarting API..."
docker compose restart api
sleep 5
echo "   ✅ API restarted"

# Step 4: Test the models endpoint
echo ""
echo "4. Testing /models endpoint..."
curl -s "http://localhost:8000/api/predictions/models" | python3 -c "
import sys, json
try:
    models = json.load(sys.stdin)
    print('   Available models:')
    for m in models:
        default = ' (DEFAULT)' if m.get('is_default') else ''
        print(f\"   - {m['model_id']}: {m['display_name']}{default}\")
except Exception as e:
    print(f'   ❌ Error: {e}')
"

# Step 5: Test Pure Elo predictions
echo ""
echo "5. Testing Pure Elo model..."
RESPONSE=$(curl -s "http://localhost:8000/api/predictions?season=2025&week=3&model=elo")
echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data:
        game = data[0]
        print(f\"   ✅ Pure Elo working: {game['away_team']} @ {game['home_team']} = {game['home_win_probability']*100:.1f}%\")
except:
    print('   ❌ Error getting predictions')
"

# Step 6: Test Recent Form model
echo ""
echo "6. Testing Elo + Recent Form model..."
RESPONSE=$(curl -s "http://localhost:8000/api/predictions?season=2025&week=3&model=elo_recent")
echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data:
        game = data[0]
        print(f\"   ✅ Recent Form working: {game['away_team']} @ {game['home_team']} = {game['home_win_probability']*100:.1f}%\")
        if 'home_form' in game and game['home_form']:
            print(f\"   📊 Home team momentum: {game['home_form'].get('momentum', 'unknown')}\")
except:
    print('   ❌ Error getting predictions')
"

# Step 7: Compare the two models
echo ""
echo "7. Comparing model predictions for Week 3..."
echo ""
echo "   Game                    | Pure Elo | Recent Form | Difference"
echo "   ------------------------|----------|-------------|------------"

curl -s "http://localhost:8000/api/predictions?season=2025&week=3&model=elo" > /tmp/elo_pure.json
curl -s "http://localhost:8000/api/predictions?season=2025&week=3&model=elo_recent" > /tmp/elo_recent.json

python3 -c "
import json

with open('/tmp/elo_pure.json') as f:
    pure = json.load(f)
with open('/tmp/elo_recent.json') as f:
    recent = json.load(f)

if pure and recent:
    for i in range(min(5, len(pure))):  # Show first 5 games
        p = pure[i]
        r = recent[i]
        game = f\"{p['away_team']:3} @ {p['home_team']:3}\"
        pure_prob = p['home_win_probability'] * 100
        recent_prob = r['home_win_probability'] * 100
        diff = recent_prob - pure_prob
        
        symbol = '↑' if diff > 0 else '↓' if diff < 0 else '='
        print(f\"   {game:23} | {pure_prob:7.1f}% | {recent_prob:10.1f}% | {diff:+6.1f}% {symbol}\")
"

# Step 8: Test hot/cold teams
echo ""
echo "8. Hot and Cold teams (Recent Form)..."
echo ""
echo "   🔥 HOT TEAMS:"
curl -s "http://localhost:8000/api/predictions/hot-teams" | python3 -c "
import sys, json
try:
    teams = json.load(sys.stdin)
    for t in teams[:3]:
        print(f\"   - {t['team_name']}: {t['momentum']} ({t['recent_record']})\")
except:
    print('   No data')
"

echo ""
echo "   🧊 COLD TEAMS:"
curl -s "http://localhost:8000/api/predictions/cold-teams" | python3 -c "
import sys, json
try:
    teams = json.load(sys.stdin)
    for t in teams[:3]:
        print(f\"   - {t['team_name']}: {t['momentum']} ({t['recent_record']})\")
except:
    print('   No data')
"

echo ""
echo "=========================================="
echo "✅ MULTI-MODEL DEPLOYMENT COMPLETE!"
echo "=========================================="
echo ""
echo "Frontend Integration:"
echo "1. Your dropdown should call: /api/predictions?season=X&week=Y&model=MODEL_ID"
echo "2. Available model IDs: 'elo' (default) and 'elo_recent'"
echo "3. Response structure is the same, just different probabilities"
echo ""
echo "Test in your browser:"
echo "- Pure Elo: http://localhost:8000/api/predictions?season=2025&week=3&model=elo"
echo "- Recent Form: http://localhost:8000/api/predictions?season=2025&week=3&model=elo_recent"
echo "- Model List: http://localhost:8000/api/predictions/models"
echo "=========================================="