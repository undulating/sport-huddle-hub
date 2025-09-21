#!/bin/bash
# save as: ingest_week3.sh

# Configuration
API_URL="http://localhost:8000"
ADMIN_USER="admin"
ADMIN_PASS="admin123"
SEASON=2025
WEEK=3

echo "🏈 Ingesting NFL Week $WEEK, Season $SEASON"
echo "=================================="

# First check what the actual ingest endpoint is
echo "Checking available endpoints..."
curl -s "$API_URL/docs" | grep -i ingest || echo "Docs not available"

# Try different possible endpoints with basic auth
echo -e "\nTrying /api/ingest/games..."
RESPONSE=$(curl -s -X POST \
  -u "$ADMIN_USER:$ADMIN_PASS" \
  "$API_URL/api/ingest/games?season=$SEASON&week=$WEEK")

if [[ "$RESPONSE" == *"error"* ]]; then
  echo "Failed. Trying /api/ingest..."
  RESPONSE=$(curl -s -X POST \
    -u "$ADMIN_USER:$ADMIN_PASS" \
    "$API_URL/api/ingest?season=$SEASON&week=$WEEK&type=games")
  
  if [[ "$RESPONSE" == *"error"* ]]; then
    echo "Failed. Let me check your routes..."
    docker exec nflpred-api python -c "
from api.app import app
for route in app.routes:
    if 'ingest' in str(route.path):
        print(f'{route.methods} {route.path}')
"
  fi
fi

echo -e "\nResponse: $RESPONSE"

# After successful ingestion, verify moneyline data
echo -e "\n📊 Verifying moneyline data was stored..."
docker exec nflpred-db psql -U nflpred -d nflpred -c \
  "SELECT home_team_id, away_team_id, home_moneyline, away_moneyline 
   FROM games 
   WHERE season=$SEASON AND week=$WEEK 
   LIMIT 3;"