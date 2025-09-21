#!/bin/bash
# fix-stadium-field.sh - Fix the stadium_name vs stadium field issue

echo "====================================="
echo "🔧 FIXING STADIUM FIELD ERROR"
echo "====================================="
echo ""

# Fix the field name in predictions.py
echo "1. Fixing stadium field name in predictions.py..."
docker exec nflpred-api python3 -c "
# Read the file
with open('/app/api/routes/predictions.py', 'r') as f:
    content = f.read()

# Replace stadium_name with stadium
content = content.replace('game.stadium_name', 'game.stadium')

# Save the fixed file
with open('/app/api/routes/predictions.py', 'w') as f:
    f.write(content)

print('✅ Fixed stadium field name')
"

# Restart API
echo ""
echo "2. Restarting API..."
docker compose restart api
sleep 5

# Test the fix
echo ""
echo "3. Testing predictions endpoint..."
for model in "elo" "elo_recent"; do
    echo ""
    echo "Testing model: $model"
    RESPONSE=$(curl -s "http://localhost:8000/api/predictions/?season=2025&week=3&model=$model" 2>/dev/null)
    
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
        print(f'  Stadium: {game.get(\"stadium\", \"N/A\")}')
    else:
        print(f'  ⚠️ Empty list returned')
except Exception as e:
    print(f'  ❌ Error: {e}')
    raw = sys.stdin.read()[:200]
    print(f'  Raw: {raw}')
"
    fi
done

echo ""
echo "====================================="
echo "✅ FIX APPLIED"
echo "====================================="
echo ""
echo "If predictions are working now, great!"
echo "The issue was: game.stadium_name should be game.stadium"