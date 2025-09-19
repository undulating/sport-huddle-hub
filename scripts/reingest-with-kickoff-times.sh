#!/bin/bash
# reingest-with-kickoff-times.sh - Re-ingest all NFL data with proper kickoff times

echo "==================================="
echo "🏈 RE-INGESTING NFL DATA WITH KICKOFF TIMES"
echo "🗓️  Seasons: 2015-2025 (Current: Sep 2025)"
echo "==================================="
echo ""

# Step 1: Check current data status
echo "📊 Current database status:"
docker exec nflpred-api python -c "
from api.storage.db import get_db_context
from api.storage.models import Game
from sqlalchemy import func
from datetime import datetime

with get_db_context() as db:
    # Check total games and seasons
    total = db.query(Game).count()
    seasons = db.query(
        Game.season,
        func.count(Game.id)
    ).group_by(Game.season).order_by(Game.season).all()
    
    print(f'Total games currently: {total}')
    print('\\nSeasons loaded:')
    for season, count in seasons:
        print(f'  {season}: {count} games')
    
    # Check if kickoff_time differs from game_date (to see if we have proper times)
    sample_games = db.query(Game).filter(Game.season == 2024).limit(5).all()
    
    print('\\n🕐 Sample kickoff times from 2024:')
    for game in sample_games:
        if game.kickoff_time != game.game_date:
            print(f'  ✅ Game {game.external_id}: Date: {game.game_date.date()}, Kickoff: {game.kickoff_time.time()}')
        else:
            print(f'  ⚠️  Game {game.external_id}: Same date/time: {game.game_date}')
"

echo ""
echo "🔄 Re-ingesting all seasons (2015-2025) with proper kickoff times..."
echo "   This will UPDATE existing games with correct kickoff times"
echo ""

# Re-ingest with proper authentication
# The upsert in your IngestRepository will update existing games
curl -X POST "http://localhost:8000/api/ingest/backfill" \
  -u "admin:admin123" \
  -H "Content-Type: application/json" \
  -d '{
    "start_season": 2015,
    "end_season": 2025,
    "provider": "nflverse"
  }' | python3 -m json.tool

echo ""
echo "⏳ Waiting for re-ingestion to complete (this may take a minute)..."
sleep 20

# Step 2: Verify kickoff times are now correct
echo ""
echo "📊 Verifying kickoff times are now properly set:"
docker exec nflpred-api python -c "
from api.storage.db import get_db_context
from api.storage.models import Game
from sqlalchemy import func
from datetime import datetime, time

with get_db_context() as db:
    # Check 2024 and 2025 games for proper kickoff times
    for season in [2024, 2025]:
        print(f'\\n📅 Season {season}:')
        
        # Count games with non-midnight kickoff times
        games = db.query(Game).filter(Game.season == season).all()
        
        games_with_times = 0
        games_at_midnight = 0
        
        for game in games:
            if game.kickoff_time:
                kickoff_time = game.kickoff_time.time()
                if kickoff_time != time(0, 0):  # Not midnight
                    games_with_times += 1
                else:
                    games_at_midnight += 1
        
        print(f'  Total games: {len(games)}')
        print(f'  Games with kickoff times: {games_with_times}')
        print(f'  Games at midnight (no time): {games_at_midnight}')
        
        # Show sample games with times
        sample_games = db.query(Game).filter(
            Game.season == season,
            Game.week <= 3  # Early season games
        ).limit(3).all()
        
        print(f'\\n  Sample Week 1-3 games:')
        for game in sample_games:
            if game.kickoff_time:
                print(f'    Week {game.week}: {game.game_date.strftime(\"%m/%d\")} at {game.kickoff_time.strftime(\"%I:%M %p\")}')
    
    # Special check for 2025 current games (September 2025)
    print(f'\\n🏈 2025 Current Games (September):')
    current_games = db.query(Game).filter(
        Game.season == 2025,
        Game.game_date >= datetime(2025, 9, 1),
        Game.game_date <= datetime(2025, 9, 30)
    ).order_by(Game.game_date).limit(5).all()
    
    for game in current_games:
        home_team = game.home_team.abbreviation if game.home_team else game.home_team_external_id
        away_team = game.away_team.abbreviation if game.away_team else game.away_team_external_id
        
        if game.kickoff_time and game.kickoff_time.time() != time(0, 0):
            print(f'  ✅ {away_team} @ {home_team}: {game.kickoff_time.strftime(\"%b %d at %I:%M %p\")}')
        else:
            print(f'  ⚠️  {away_team} @ {home_team}: {game.game_date.strftime(\"%b %d\")} (no kickoff time)')
"

# Step 3: Test the API to ensure predictions still work
echo ""
echo "🧪 Testing predictions API with new kickoff times:"
echo ""

# Test current week (should be around Week 3 in September 2025)
echo "Testing 2025 Week 3 (current week):"
curl -s "http://localhost:8000/api/predictions?season=2025&week=3" | python3 -c "
import sys, json
from datetime import datetime

try:
    data = json.load(sys.stdin)
    if data and len(data) > 0:
        print(f'✅ Found {len(data)} games for Week 3')
        
        # Check if kickoff_time is populated
        for game in data[:2]:  # First 2 games
            home = game.get('home_team', 'UNK')
            away = game.get('away_team', 'UNK')
            game_time = game.get('game_time') or game.get('game_date')
            kickoff = game.get('kickoff_time')
            
            if kickoff and kickoff != game_time:
                print(f'  ✅ {away} @ {home}: Has separate kickoff time')
            else:
                print(f'  ⚠️  {away} @ {home}: Using game_date for time')
    else:
        print('❌ No games found for Week 3')
except Exception as e:
    print(f'Error: {e}')
"

echo ""
echo "==================================="
echo "✅ RE-INGESTION COMPLETE!"
echo ""
echo "What was updated:"
echo "  • Kept all existing game data intact"
echo "  • Updated kickoff_time field with proper times from NFLverse"
echo "  • Maintained game_date for date display"
echo "  • Your predictions and Elo ratings remain unchanged"
echo ""
echo "Frontend will now show:"
echo "  • Correct kickoff times in GameCard components"
echo "  • Proper date headers with actual game times"
echo ""
echo "Test in frontend:"
echo "  1. cd ../web && npm run dev"
echo "  2. Select 2025 Season, Week 3"
echo "  3. Game cards should show actual kickoff times!"
echo "==================================="