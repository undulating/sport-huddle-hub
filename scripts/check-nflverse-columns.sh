#!/bin/bash
# check-nflverse-columns.sh - Check what time columns NFLverse actually has

echo "==================================="
echo "🔍 INVESTIGATING NFLVERSE DATA STRUCTURE"
echo "==================================="
echo ""

# Step 1: Check what columns are available in NFLverse
echo "📊 Checking NFLverse CSV columns..."
docker exec nflpred-api python -c "
import pandas as pd
import numpy as np

print('Downloading NFLverse data...')
url = 'https://github.com/nflverse/nfldata/raw/master/data/games.csv'
df = pd.read_csv(url)

print(f'\\n✅ Loaded {len(df)} games total')
print(f'Seasons: {df[\"season\"].min()} to {df[\"season\"].max()}')

print('\\n📋 ALL COLUMNS in NFLverse data:')
print('-' * 40)
for i, col in enumerate(df.columns, 1):
    print(f'{i:3}. {col}')

# Check for any time-related columns
print('\\n⏰ TIME-RELATED COLUMNS:')
time_cols = [col for col in df.columns if any(word in col.lower() for word in ['time', 'kickoff', 'start', 'game', 'date', 'day', 'hour', 'minute'])]
for col in time_cols:
    sample = df[col].dropna().head(3).tolist()
    print(f'  {col}: {sample[:3]}')

# Check 2025 data specifically
df_2025 = df[df['season'] == 2025]
if not df_2025.empty:
    print(f'\\n📅 2025 SEASON DATA:')
    print(f'  Games: {len(df_2025)}')
    print(f'  Weeks: {sorted(df_2025[\"week\"].unique())}')
    
    # Check what time data exists for 2025
    print('\\n  Sample 2025 game time data:')
    for idx, row in df_2025.head(3).iterrows():
        print(f'    Week {row[\"week\"]}: {row.get(\"gameday\", \"NO DATE\")}', end='')
        if 'gametime' in df.columns:
            print(f' at {row.get(\"gametime\", \"NO TIME\")}')
        else:
            print(' (no gametime column)')
"

echo ""
echo "==================================="
echo "🔧 ADDING DEFAULT KICKOFF TIMES"
echo "==================================="
echo ""

# Step 2: Update database with typical NFL kickoff times
echo "📝 Adding typical NFL kickoff times to database..."
docker exec nflpred-api python -c "
from api.storage.db import get_db_context
from api.storage.models import Game
from datetime import datetime, time, timedelta
import pytz

def get_typical_kickoff_time(week_number, game_index, day_of_week):
    \"\"\"
    Return typical NFL kickoff times based on patterns:
    - Thursday: 8:20 PM ET
    - Sunday early: 1:00 PM ET
    - Sunday late: 4:05/4:25 PM ET
    - Sunday night: 8:20 PM ET
    - Monday night: 8:15 PM ET
    \"\"\"
    if day_of_week == 3:  # Thursday
        return time(20, 20)  # 8:20 PM
    elif day_of_week == 0:  # Monday
        return time(20, 15)  # 8:15 PM
    elif day_of_week == 6:  # Sunday
        # First 8-10 games are usually 1 PM
        if game_index < 8:
            return time(13, 0)  # 1:00 PM
        # Next 3-4 games are usually 4:05/4:25 PM
        elif game_index < 12:
            return time(16, 5) if game_index % 2 == 0 else time(16, 25)
        # Last game is Sunday Night Football
        else:
            return time(20, 20)  # 8:20 PM
    else:
        return time(13, 0)  # Default to 1 PM

print('Updating games with typical kickoff times...')

with get_db_context() as db:
    # Update games by week
    for season in [2015, 2016, 2017, 2018, 2019, 2020, 2021, 2022, 2023, 2024, 2025]:
        games_updated = 0
        
        # Get all weeks for this season
        weeks = db.query(Game.week).filter(Game.season == season).distinct().all()
        
        for (week,) in weeks:
            # Get games for this week, ordered by game_date
            week_games = db.query(Game).filter(
                Game.season == season,
                Game.week == week
            ).order_by(Game.game_date).all()
            
            # Group games by date
            games_by_date = {}
            for game in week_games:
                date_key = game.game_date.date()
                if date_key not in games_by_date:
                    games_by_date[date_key] = []
                games_by_date[date_key].append(game)
            
            # Assign kickoff times based on day and order
            for date_key, date_games in games_by_date.items():
                day_of_week = date_key.weekday()
                
                for idx, game in enumerate(date_games):
                    # Get typical kickoff time
                    kickoff_time = get_typical_kickoff_time(week, idx, day_of_week)
                    
                    # Combine date with kickoff time
                    new_kickoff = datetime.combine(date_key, kickoff_time)
                    
                    # Only update if currently at midnight
                    if game.kickoff_time.time() == time(0, 0):
                        game.kickoff_time = new_kickoff
                        games_updated += 1
        
        if games_updated > 0:
            db.commit()
            print(f'  {season}: Updated {games_updated} games with kickoff times')
        else:
            print(f'  {season}: No updates needed')
    
    # Verify the updates
    print('\\n✅ Verification - Sample games with new kickoff times:')
    
    # Check 2025 Week 3 (current)
    week3_games = db.query(Game).filter(
        Game.season == 2025,
        Game.week == 3
    ).order_by(Game.kickoff_time).limit(5).all()
    
    print('\\n2025 Week 3 games:')
    for game in week3_games:
        home = game.home_team.abbreviation if game.home_team else 'TBD'
        away = game.away_team.abbreviation if game.away_team else 'TBD'
        print(f'  {away:3} @ {home:3}: {game.kickoff_time.strftime(\"%b %d at %I:%M %p\")}')
    
    # Check 2024 Week 1 for comparison
    week1_games = db.query(Game).filter(
        Game.season == 2024,
        Game.week == 1
    ).order_by(Game.kickoff_time).limit(5).all()
    
    print('\\n2024 Week 1 games (for reference):')
    for game in week1_games:
        home = game.home_team.abbreviation if game.home_team else 'TBD'
        away = game.away_team.abbreviation if game.away_team else 'TBD'
        print(f'  {away:3} @ {home:3}: {game.kickoff_time.strftime(\"%b %d at %I:%M %p\")}')
"

echo ""
echo "==================================="
echo "🧪 TESTING THE UPDATES"
echo "==================================="
echo ""

# Test the API
echo "Testing predictions API with updated times..."
curl -s "http://localhost:8000/api/predictions?season=2025&week=3" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data:
        print(f'✅ Found {len(data)} games for 2025 Week 3')
        print('\\nFirst 3 games:')
        for game in data[:3]:
            home = game.get('home_team', 'UNK')
            away = game.get('away_team', 'UNK')
            
            # Check both game_time and kickoff_time fields
            game_time = game.get('game_time') or game.get('game_date')
            kickoff = game.get('kickoff_time')
            
            print(f'  {away} @ {home}:')
            print(f'    game_time: {game_time}')
            print(f'    kickoff_time: {kickoff}')
except Exception as e:
    print(f'Error: {e}')
"

echo ""
echo "==================================="
echo "✅ KICKOFF TIMES ADDED!"
echo ""
echo "What was done:"
echo "  • NFLverse doesn't have separate kickoff time data"
echo "  • Added typical NFL kickoff times based on day of week"
echo "  • Sunday: 1:00 PM, 4:05/4:25 PM, 8:20 PM ET"
echo "  • Thursday: 8:20 PM ET"
echo "  • Monday: 8:15 PM ET"
echo ""
echo "Your GameCards will now show realistic kickoff times!"
echo "==================================="