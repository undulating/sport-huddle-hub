#!/bin/bash

# update-player-stats.sh
# Run this weekly to get latest player stats

SEASON=2025
CURRENT_WEEK=3  # Update this each week

echo "Updating player stats for Season $SEASON, Week $CURRENT_WEEK..."

# Sync the current week
curl -X POST "http://localhost:8000/api/ingest/sync" \
  -u admin:admin123 \
  -H "Content-Type: application/json" \
  -d "{
    \"season\": $SEASON,
    \"week\": $CURRENT_WEEK,
    \"provider\": \"nflverse_r\"
  }"

echo "Player stats updated!"
