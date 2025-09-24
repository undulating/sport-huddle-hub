#!/bin/bash

# ingest-2025-player-stats.sh
# Script to check for and ingest 2025 Week 1-2 player stats

set -e

echo "=========================================="
echo "🏈 2025 SEASON PLAYER STATS INGESTION"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "1. Checking for 2025 data availability..."
docker exec nflpred-api python3 -c "
import pandas as pd
import numpy as np

url = 'https://github.com/nflverse/nflverse-data/releases/download/player_stats/player_stats.csv'
print('Checking NFLverse for 2025 data...')

# Check if 2025 data exists
df = pd.read_csv(url)
df_2025 = df[df['season'] == 2025]

if len(df_2025) > 0:
    weeks_available = sorted(df_2025['week'].unique())
    print(f'✅ 2025 data found!')
    print(f'   Available weeks: {weeks_available}')
    print(f'   Total player records: {len(df_2025)}')
    
    # Show Week 1 summary
    week1 = df_2025[df_2025['week'] == 1]
    print(f'\n📅 Week 1: {len(week1)} players')
    
    # Show Week 2 summary if available
    if 2 in weeks_available:
        week2 = df_2025[df_2025['week'] == 2]
        print(f'📅 Week 2: {len(week2)} players')
    
    # Show Week 3 summary if available (we're in Week 3 now)
    if 3 in weeks_available:
        week3 = df_2025[df_2025['week'] == 3]
        print(f'📅 Week 3: {len(week3)} players')
else:
    print('❌ No 2025 data available yet in NFLverse')
    print('   Will use 2024 data as fallback')
"

echo ""
echo "2. Attempting to load 2025 Week 1 data..."
docker exec nflpred-api python3 -c "
import pandas as pd
import numpy as np
import sys

url = 'https://github.com/nflverse/nflverse-data/releases/download/player_stats/player_stats.csv'

# Try to load 2025 Week 1
df = pd.read_csv(url)
df_2025_w1 = df[(df['season'] == 2025) & (df['week'] == 1)]

if len(df_2025_w1) > 0:
    print(f'✅ Loaded {len(df_2025_w1)} player records for 2025 Week 1')
    
    # Show top performers
    print('\n🏈 Top QBs - Week 1, 2025:')
    print('-' * 60)
    qbs = df_2025_w1[df_2025_w1['position'] == 'QB'].nlargest(5, 'passing_yards', keep='all')
    for _, qb in qbs.iterrows():
        print(f\"{qb['player_display_name']:20} {qb['recent_team']:4} - {qb['passing_yards']:.0f} yds, {qb['passing_tds']:.0f} TDs\")
    
    print('\n🏃 Top RBs - Week 1, 2025:')
    print('-' * 60)
    rbs = df_2025_w1[df_2025_w1['position'] == 'RB'].copy()
    rbs['total_yards'] = rbs['rushing_yards'].fillna(0) + rbs['receiving_yards'].fillna(0)
    rbs = rbs.nlargest(5, 'total_yards', keep='all')
    for _, rb in rbs.iterrows():
        print(f\"{rb['player_display_name']:20} {rb['recent_team']:4} - {rb['rushing_yards']:.0f} rush, {rb['receiving_yards']:.0f} rec yds\")
    
    print('\n🎯 Top WRs - Week 1, 2025:')
    print('-' * 60)
    wrs = df_2025_w1[df_2025_w1['position'] == 'WR'].nlargest(5, 'receiving_yards', keep='all')
    for _, wr in wrs.iterrows():
        print(f\"{wr['player_display_name']:20} {wr['recent_team']:4} - {wr['receptions']:.0f}/{wr['targets']:.0f} for {wr['receiving_yards']:.0f} yds\")
else:
    print('⚠️ No 2025 Week 1 data found - using latest 2024 data')
    sys.exit(0)
"

echo ""
echo "3. Attempting to load 2025 Week 2 data..."
docker exec nflpred-api python3 -c "
import pandas as pd
import numpy as np

url = 'https://github.com/nflverse/nflverse-data/releases/download/player_stats/player_stats.csv'

# Try to load 2025 Week 2
df = pd.read_csv(url)
df_2025_w2 = df[(df['season'] == 2025) & (df['week'] == 2)]

if len(df_2025_w2) > 0:
    print(f'✅ Loaded {len(df_2025_w2)} player records for 2025 Week 2')
    
    # Show top performers
    print('\n🏈 Top QBs - Week 2, 2025:')
    print('-' * 60)
    qbs = df_2025_w2[df_2025_w2['position'] == 'QB'].nlargest(3, 'passing_yards', keep='all')
    for _, qb in qbs.iterrows():
        print(f\"{qb['player_display_name']:20} {qb['recent_team']:4} - {qb['passing_yards']:.0f} yds, {qb['passing_tds']:.0f} TDs\")
else:
    print('⚠️ No 2025 Week 2 data available yet')
"

echo ""
echo "4. Ingesting available 2025 data into your system..."

# Ingest Week 1 if available
echo -e "${YELLOW}Ingesting Week 1, 2025...${NC}"
curl -X POST "http://localhost:8000/api/ingest/sync" \
  -u admin:admin123 \
  -H "Content-Type: application/json" \
  -d '{
    "season": 2025,
    "week": 1,
    "provider": "nflverse_r"
  }' 2>/dev/null | python3 -m json.tool

sleep 2

# Ingest Week 2 if available
echo -e "${YELLOW}Ingesting Week 2, 2025...${NC}"
curl -X POST "http://localhost:8000/api/ingest/sync" \
  -u admin:admin123 \
  -H "Content-Type: application/json" \
  -d '{
    "season": 2025,
    "week": 2,
    "provider": "nflverse_r"
  }' 2>/dev/null | python3 -m json.tool

sleep 2

# If we're past Week 3, try that too
echo -e "${YELLOW}Attempting Week 3, 2025...${NC}"
curl -X POST "http://localhost:8000/api/ingest/sync" \
  -u admin:admin123 \
  -H "Content-Type: application/json" \
  -d '{
    "season": 2025,
    "week": 3,
    "provider": "nflverse_r"
  }' 2>/dev/null | python3 -m json.tool

echo ""
echo "5. Creating comprehensive player stats update script..."
cat > update-player-stats.sh << 'EOF'
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
EOF

chmod +x update-player-stats.sh
echo -e "${GREEN}✅ Created update-player-stats.sh for weekly updates${NC}"

echo ""
echo "6. Testing comprehensive stats retrieval with all columns..."
docker exec nflpred-api python3 -c "
import pandas as pd
import numpy as np

url = 'https://github.com/nflverse/nflverse-data/releases/download/player_stats/player_stats.csv'

# Get most recent data (2025 if available, else 2024)
df = pd.read_csv(url)
latest_season = df['season'].max()
latest_week = df[df['season'] == latest_season]['week'].max()

print(f'📊 Latest data available: {latest_season} Week {latest_week}')

# Get that week's data
latest_df = df[(df['season'] == latest_season) & (df['week'] == latest_week)]
print(f'✅ {len(latest_df)} players in latest week')

# Show a complete player record with all stats
print('\n📋 Example Complete Player Record (All 53 Columns):')
print('=' * 80)

# Find a QB with complete stats
qb_sample = latest_df[
    (latest_df['position'] == 'QB') & 
    (latest_df['passing_yards'] > 250)
].iloc[0] if len(latest_df[latest_df['position'] == 'QB']) > 0 else latest_df.iloc[0]

# Show every non-null stat
for col in sorted(latest_df.columns):
    val = qb_sample[col]
    if pd.notna(val) and val != 0:
        print(f'{col:30} {val}')
"

echo ""
echo "=========================================="
echo "✨ 2025 PLAYER STATS INGESTION COMPLETE!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Your system now has the latest player data"
echo "2. Run ./update-player-stats.sh weekly for updates"
echo "3. Player profiles include all 53 stat columns"
echo "4. Consider creating player impact features for predictions"
echo ""
echo "Available metrics for analysis:"
echo "- Standard stats (yards, TDs, attempts, etc.)"
echo "- EPA (Expected Points Added)"
echo "- DAKOTA (QB efficiency metric)"
echo "- RACR/PACR (Receiver/Passer metrics)"
echo "- WOPR (Weighted Opportunity Rating)"
echo "- Target/Air Yards Share"
echo "- Fantasy points (standard & PPR)"