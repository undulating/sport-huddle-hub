#!/bin/bash
# elo-quick-update.sh - Quick update after Sunday games

echo "🏈 QUICK ELO UPDATE - After Sunday Games"
echo "========================================"
echo ""

# Just update based on last 3 days (Thurs/Sun/Mon games)
docker exec nflpred-api python -c "
import sys
sys.path.append('/app')
from api.scripts.elo_utilities import EloManager
manager = EloManager()
manager.quick_retrain_recent(days_back=3)
"

# Test predictions still work
echo ""
echo "Testing predictions..."
curl -s "http://localhost:8000/api/predictions?season=2025&week=3" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data:
    print(f'✅ Predictions working! {len(data)} games returned')
"

---







