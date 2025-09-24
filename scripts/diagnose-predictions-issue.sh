#!/bin/bash
# diagnose-predictions-issue.sh - Diagnose and fix the predictions not showing

echo "====================================="
echo "🔍 DIAGNOSING PREDICTIONS ISSUE"
echo "====================================="
echo ""

# Step 1: Check API logs for the actual error
echo "1. Checking recent API logs for errors..."
docker compose logs api --tail=20 | grep -E "ERROR|TypeError|predict_game" || echo "No recent errors in logs"

# Step 2: Test the API endpoint directly
echo ""
echo "2. Testing predictions endpoint directly..."
RESPONSE=$(curl -s "http://localhost:8000/api/predictions?season=2025&week=3&model=elo" 2>/dev/null)

if [ -z "$RESPONSE" ]; then
    echo "❌ No response from API"
else
    echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, list):
        print(f'✅ Got {len(data)} predictions')
        if len(data) > 0:
            print(f'  Example: {data[0].get(\"away_team\", \"?\")} @ {data[0].get(\"home_team\", \"?\")}')
    else:
        print(f'❌ Unexpected response: {data}')
except Exception as e:
    print(f'❌ Parse error: {e}')
    print(f'Raw response: {sys.stdin.read()[:200]}')
" || echo "Parse failed"
fi

# Step 3: Check the actual error by running predictions directly
echo ""
echo "3. Running predictions directly in container to see error..."
docker exec nflpred-api python3 -c "
import sys
sys.path.append('/app')

# Set up logging to see errors
import logging
logging.basicConfig(level=logging.DEBUG)

from api.routes.predictions import get_predictions
from api.storage.db import get_db_context
from api.models.elo_model import EloModel

# Test the models directly
print('Testing EloModel.predict_game signature...')
elo = EloModel()
elo.load_ratings_from_db()

# Check the method signature
import inspect
sig = inspect.signature(elo.predict_game)
print(f'predict_game expects: {sig}')
print(f'Parameters: {list(sig.parameters.keys())}')

# Try calling it
try:
    result = elo.predict_game(1, 2)  # Just team IDs
    print('✅ 2-argument call works')
except Exception as e:
    print(f'❌ 2-argument call failed: {e}')

try:
    from datetime import datetime
    result = elo.predict_game(1, 2, datetime.now())  # With date
    print('✅ 3-argument call works')
except TypeError as e:
    print(f'❌ 3-argument call failed (expected): {e}')
" 2>&1

# Step 4: Apply the fix
echo ""
echo "4. Applying fix to predictions.py..."
docker exec nflpred-api bash -c 'cat > /tmp/fix_predictions.py << "EOF"
import fileinput
import sys

# Read the predictions.py file and fix the predict_game call
with open("/app/api/routes/predictions.py", "r") as f:
    lines = f.readlines()

fixed_lines = []
skip_next = False
for i, line in enumerate(lines):
    if skip_next:
        skip_next = False
        continue
    
    if "pred = prediction_model.predict_game(" in line:
        # Check if this is a multi-line call
        if i + 2 < len(lines) and "game.game_date" in lines[i + 2]:
            # Fix multi-line call - remove the game_date line
            fixed_lines.append(line)
            fixed_lines.append(lines[i + 1])  # Keep the team IDs
            # Skip the game_date line
            if i + 3 < len(lines) and ")" in lines[i + 3]:
                fixed_lines.append(lines[i + 3])  # Keep the closing paren
                skip_next = True  # Skip processing the next lines
            continue
        elif "game.game_date" in line:
            # Single line call with date - remove it
            fixed_line = line.replace(", game.game_date", "")
            fixed_lines.append(fixed_line)
        else:
            fixed_lines.append(line)
    else:
        fixed_lines.append(line)

# Write the fixed file
with open("/app/api/routes/predictions.py", "w") as f:
    f.writelines(fixed_lines)

print("✅ Fixed predictions.py - removed game_date from predict_game calls")
EOF
python3 /tmp/fix_predictions.py'

# Step 5: Restart the API
echo ""
echo "5. Restarting API to apply changes..."
docker compose restart api
sleep 5

# Step 6: Test again
echo ""
echo "6. Testing predictions after fix..."
for model in "elo" "elo_recent"; do
    echo ""
    echo "Testing model: $model"
    RESPONSE=$(curl -s "http://localhost:8000/api/predictions?season=2025&week=3&model=$model" 2>/dev/null)
    
    if [ -z "$RESPONSE" ]; then
        echo "  ❌ No response"
    else
        echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, list) and len(data) > 0:
        print(f'  ✅ SUCCESS! Got {len(data)} predictions')
        game = data[0]
        print(f'  Example: {game[\"away_team\"]} @ {game[\"home_team\"]}')
        print(f'  Home Win: {game[\"home_win_probability\"]*100:.1f}%')
        print(f'  Model: {game.get(\"model_used\", \"unknown\")}')
    else:
        print(f'  ❌ No games returned')
except Exception as e:
    print(f'  ❌ Error: {e}')
" || echo "  Parse failed"
    fi
done

echo ""
echo "====================================="
echo "📋 DIAGNOSIS COMPLETE"
echo "====================================="
echo ""
echo "The issue was that predict_game() was being called with 3 arguments"
echo "(including game.game_date) but the models only accept 2 arguments."
echo ""
echo "If predictions are now working, great!"
echo "If not, check the logs with: docker compose logs api --tail=50"