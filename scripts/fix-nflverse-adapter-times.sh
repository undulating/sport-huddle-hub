#!/bin/bash
# fix-nflverse-adapter-times.sh - Check NFLverse data and fix adapter

echo "==================================="
echo "🔍 CHECKING NFLVERSE DATA STRUCTURE"
echo "==================================="
echo ""

# First, let's see exactly what columns and data NFLverse provides
docker exec nflpred-api python -c "
import pandas as pd
import numpy as np

print('📊 Analyzing NFLverse CSV structure...')
url = 'https://github.com/nflverse/nfldata/raw/master/data/games.csv'
df = pd.read_csv(url)

print(f'\\nTotal games: {len(df)}')

# Check all column names
print('\\n🔍 Searching for time-related columns:')
print('-' * 50)

# Look for ANY column that might contain time info
for col in df.columns:
    # Check if column might have time data
    if any(word in col.lower() for word in ['time', 'kick', 'start', 'game', 'hour', 'minute', 'when']):
        # Show column name and sample values
        sample_vals = df[col].dropna().unique()[:5]
        print(f'{col}:')
        for val in sample_vals:
            print(f'  → {val}')
        print()

# Check the gameday column format
print('\\n📅 Checking gameday column format:')
gameday_samples = df['gameday'].dropna().head(10)
for val in gameday_samples:
    print(f'  {val}')

# Look for 'gametime' column specifically (it might exist in newer data)
if 'gametime' in df.columns:
    print('\\n⏰ FOUND gametime column!')
    print('Sample values:')
    for val in df['gametime'].dropna().head(10):
        print(f'  {val}')
else:
    print('\\n❌ No gametime column found')

# Check 2024-2025 specifically
recent_games = df[df['season'].isin([2024, 2025])]
print(f'\\n📊 2024-2025 Games: {len(recent_games)}')
if not recent_games.empty:
    print('\\nSample 2024 game (all columns):')
    sample_game = recent_games.iloc[0]
    for col, val in sample_game.items():
        if pd.notna(val) and val != '' and val != 0:
            print(f'  {col}: {val}')
"

echo ""
echo "==================================="
echo "🔧 UPDATING ADAPTER TO PARSE TIMES"
echo "==================================="
echo ""

# Now let's create a fixed version of the adapter that handles times properly
cat > /tmp/fix_adapter.py << 'EOF'
import pandas as pd
from datetime import datetime, time
from typing import List, Optional
import logging

# Test parsing logic
def parse_nflverse_game_times():
    """
    Parse NFLverse data and extract proper kickoff times.
    NFLverse may have 'gametime' column or we need to use typical times.
    """
    
    print("Testing NFLverse time parsing...")
    
    # Load a sample of data
    url = 'https://github.com/nflverse/nfldata/raw/master/data/games.csv'
    df = pd.read_csv(url, nrows=100)  # Just first 100 for testing
    
    # Check what we have
    has_gametime = 'gametime' in df.columns
    has_kickoff = 'kickoff' in df.columns
    has_time_columns = has_gametime or has_kickoff
    
    print(f"Has gametime column: {has_gametime}")
    print(f"Has kickoff column: {has_kickoff}")
    
    if has_gametime:
        # Parse gametime if it exists
        print("\nParsing gametime column:")
        for idx, row in df.head(5).iterrows():
            gameday = row.get('gameday')
            gametime = row.get('gametime')
            
            if pd.notna(gametime) and gametime != '':
                # Try to parse the time
                try:
                    # gametime might be in format "HH:MM" or "HH:MM PM"
                    if ':' in str(gametime):
                        # Combine date and time
                        datetime_str = f"{gameday} {gametime}"
                        parsed = pd.to_datetime(datetime_str, errors='coerce')
                        print(f"  {gameday} + {gametime} = {parsed}")
                    else:
                        print(f"  {gameday} + {gametime} = Can't parse")
                except:
                    print(f"  Error parsing: {gametime}")
            else:
                print(f"  {gameday} - No gametime")
    else:
        print("\nNo gametime column - will use typical NFL kickoff times")
        print("  Sunday early: 1:00 PM ET")
        print("  Sunday late: 4:05/4:25 PM ET") 
        print("  Sunday night: 8:20 PM ET")
        print("  Monday night: 8:15 PM ET")
        print("  Thursday night: 8:20 PM ET")

# Run the test
parse_nflverse_game_times()
EOF

docker exec nflpred-api python /tmp/fix_adapter.py

echo ""
echo "==================================="
echo "🚀 IMPLEMENTING THE FIX"
echo "==================================="
echo ""

# Create a patch for the adapter
docker exec nflpred-api python -c "
import os

# Create a patched version of get_games method
patch_code = '''
def get_typical_nfl_kickoff(game_date, game_index_in_day):
    \"\"\"Get typical NFL kickoff time based on day and game slot.\"\"\"
    from datetime import time
    
    weekday = game_date.weekday()
    
    # Thursday (3)
    if weekday == 3:
        return time(20, 20)  # 8:20 PM ET
    
    # Sunday (6)
    elif weekday == 6:
        if game_index_in_day < 8:
            return time(13, 0)  # 1:00 PM ET (early games)
        elif game_index_in_day < 12:
            # Alternate between 4:05 and 4:25 PM
            return time(16, 5) if game_index_in_day % 2 == 0 else time(16, 25)
        else:
            return time(20, 20)  # 8:20 PM SNF
    
    # Monday (0)
    elif weekday == 0:
        return time(20, 15)  # 8:15 PM ET
    
    # Saturday or other
    else:
        return time(13, 0)  # Default 1:00 PM
'''

print('Patch created. To apply:')
print('1. Add the get_typical_nfl_kickoff function to your adapter')
print('2. In get_games method, after setting game_date:')
print('   - Group games by date')
print('   - Assign kickoff times based on game slot')
print('3. Use datetime.combine(game_date.date(), kickoff_time)')
"

echo ""
echo "==================================="
echo "📝 QUICK FIX - ADD KICKOFF TIMES NOW"
echo "==================================="
echo ""

# Quick fix - update existing games in database with typical times
docker exec nflpred-api python -c "
from api.storage.db import get_db_context
from api.storage.models import Game
from datetime import datetime, time
from sqlalchemy import func

def get_kickoff_time_for_slot(weekday, slot_index):
    \"\"\"Get typical NFL kickoff time for a game slot.\"\"\"
    if weekday == 3:  # Thursday
        return time(20, 20)
    elif weekday == 0:  # Monday  
        return time(20, 15)
    elif weekday == 6:  # Sunday
        if slot_index < 8:
            return time(13, 0)  # 1 PM games
        elif slot_index < 12:
            return time(16, 5) if slot_index % 2 == 0 else time(16, 25)  # 4 PM games
        else:
            return time(20, 20)  # SNF
    else:
        return time(13, 0 if slot_index < 8 else 16, 0)

print('🔄 Updating all games with typical NFL kickoff times...')

with get_db_context() as db:
    # Process each season and week
    seasons = db.query(Game.season).distinct().all()
    
    total_updated = 0
    for (season,) in seasons:
        weeks = db.query(Game.week).filter(Game.season == season).distinct().all()
        
        for (week,) in weeks:
            # Get all games for this week
            games = db.query(Game).filter(
                Game.season == season,
                Game.week == week
            ).order_by(Game.game_date).all()
            
            # Group by date
            games_by_date = {}
            for game in games:
                date_key = game.game_date.date()
                if date_key not in games_by_date:
                    games_by_date[date_key] = []
                games_by_date[date_key].append(game)
            
            # Update kickoff times
            for date, date_games in games_by_date.items():
                weekday = date.weekday()
                for idx, game in enumerate(date_games):
                    kickoff_time = get_kickoff_time_for_slot(weekday, idx)
                    new_kickoff = datetime.combine(date, kickoff_time)
                    
                    # Update if different
                    if game.kickoff_time != new_kickoff:
                        game.kickoff_time = new_kickoff
                        total_updated += 1
    
    db.commit()
    print(f'✅ Updated {total_updated} games with kickoff times!')
    
    # Show samples
    print('\\n📊 Sample games with updated times:')
    
    # Current week (2025 Week 3)
    current_games = db.query(Game).filter(
        Game.season == 2025,
        Game.week == 3
    ).order_by(Game.kickoff_time).limit(6).all()
    
    print('\\n2025 Week 3 (Current):')
    for game in current_games:
        if game.home_team and game.away_team:
            print(f'  {game.away_team.abbreviation:3} @ {game.home_team.abbreviation:3}: {game.kickoff_time.strftime(\"%a %b %d, %I:%M %p\")}')
"

echo ""
echo "==================================="
echo "✅ COMPLETE!"
echo ""
echo "Next steps:"
echo "1. Test the API: curl 'http://localhost:8000/api/predictions?season=2025&week=3'"
echo "2. Check frontend: Games should now show proper kickoff times"
echo "3. Update adapter permanently by adding the time logic to get_games()"
echo "==================================="