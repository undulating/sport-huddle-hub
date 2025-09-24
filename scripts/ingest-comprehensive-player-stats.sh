#!/bin/bash

# ingest-comprehensive-player-stats.sh
# Script to ingest ALL player statistics from NFLverse into your system

set -e

echo "=========================================="
echo "🏈 COMPREHENSIVE PLAYER STATS INGESTION"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Step 1: Check all available columns
echo "1. Discovering all available player stat columns..."
docker exec nflpred-api python3 -c "
import sys
sys.path.insert(0, '/app')
from api.adapters.nflverse_r_adapter import NFLverseRAdapter

adapter = NFLverseRAdapter()
columns = adapter.get_all_player_columns(2024)

print('Available Player Stats Columns:')
print('=' * 80)

# Group columns by category
passing_cols = [c for c in columns if 'passing' in c or 'completions' in c or 'attempts' in c]
rushing_cols = [c for c in columns if 'rushing' in c or 'carries' in c]
receiving_cols = [c for c in columns if 'receiving' in c or 'targets' in c or 'receptions' in c]
advanced_cols = [c for c in columns if c in ['pacr', 'racr', 'dakota', 'wopr', 'air_yards_share', 'target_share']]
fantasy_cols = [c for c in columns if 'fantasy' in c]
other_cols = [c for c in columns if c not in passing_cols + rushing_cols + receiving_cols + advanced_cols + fantasy_cols]

print('\n📊 PASSING STATS:', len(passing_cols))
for col in passing_cols:
    print(f'  - {col}')

print('\n🏃 RUSHING STATS:', len(rushing_cols))
for col in rushing_cols:
    print(f'  - {col}')

print('\n🎯 RECEIVING STATS:', len(receiving_cols))
for col in receiving_cols:
    print(f'  - {col}')

print('\n🔬 ADVANCED METRICS:', len(advanced_cols))
for col in advanced_cols:
    print(f'  - {col}')

print('\n🏆 FANTASY STATS:', len(fantasy_cols))
for col in fantasy_cols:
    print(f'  - {col}')

print('\n📋 OTHER COLUMNS:', len(other_cols))
for col in other_cols[:20]:  # Show first 20
    print(f'  - {col}')

print(f'\n✨ TOTAL COLUMNS AVAILABLE: {len(columns)}')
"

echo ""
echo "2. Testing comprehensive player stats retrieval..."
docker exec nflpred-api python3 -c "
import sys
sys.path.insert(0, '/app')
from api.adapters.nflverse_r_adapter import NFLverseRAdapter
import pandas as pd

adapter = NFLverseRAdapter()

# Get Week 1 2025 stats with ALL columns
print('Fetching Week 1, 2025 player stats...')
df = adapter.get_comprehensive_player_stats(2025, 1)

print(f'✅ Loaded {len(df)} player records')
print(f'✅ Total columns: {len(df.columns)}')

# Show top QBs by passing yards
qbs = df[df['position'] == 'QB'].nlargest(5, 'passing_yards', keep='all')
print('\n🏈 Top 5 QBs - Week 1, 2025:')
print('-' * 60)
for _, qb in qbs.iterrows():
    print(f\"{qb['player_display_name']:20} {qb['recent_team']:4} \")
    print(f\"  Passing: {qb['passing_yards']:.0f} yds, {qb['passing_tds']:.0f} TDs\")
    if pd.notna(qb.get('dakota')):
        print(f\"  DAKOTA: {qb['dakota']:.2f}\")
    if pd.notna(qb.get('passing_epa')):
        print(f\"  EPA: {qb['passing_epa']:.2f}\")

# Show top RBs
rbs = df[df['position'] == 'RB'].nlargest(5, 'rushing_yards', keep='all')
print('\n🏃 Top 5 RBs - Week 1, 2025:')
print('-' * 60)
for _, rb in rbs.iterrows():
    print(f\"{rb['player_display_name']:20} {rb['recent_team']:4}\")
    print(f\"  Rushing: {rb['rushing_yards']:.0f} yds, {rb['rushing_tds']:.0f} TDs\")
    print(f\"  Receiving: {rb['receiving_yards']:.0f} yds on {rb['receptions']:.0f} rec\")
    print(f\"  Fantasy PPR: {rb['fantasy_points_ppr']:.1f} pts\")

# Show top WRs with advanced metrics
wrs = df[df['position'] == 'WR'].nlargest(5, 'receiving_yards', keep='all')
print('\n🎯 Top 5 WRs - Week 1, 2025:')
print('-' * 60)
for _, wr in wrs.iterrows():
    print(f\"{wr['player_display_name']:20} {wr['recent_team']:4}\")
    print(f\"  Receiving: {wr['receptions']:.0f}/{wr['targets']:.0f} for {wr['receiving_yards']:.0f} yds\")
    if pd.notna(wr.get('target_share')):
        print(f\"  Target Share: {wr['target_share']:.1%}\")
    if pd.notna(wr.get('wopr')):
        print(f\"  WOPR: {wr['wopr']:.2f}\")
    if pd.notna(wr.get('racr')):
        print(f\"  RACR: {wr['racr']:.2f}\")
"

echo ""
echo "3. Building comprehensive player profiles for 2025 season..."
docker exec nflpred-api python3 -c "
import sys
sys.path.insert(0, '/app')
from api.adapters.nflverse_r_adapter import NFLverseRAdapter
import json

adapter = NFLverseRAdapter()

# Build profiles for current season
print('Building player profiles for 2025...')
profiles = adapter.build_comprehensive_player_profiles(2025)

print(f'✅ Built profiles for {len(profiles)} players')

# Show example profile
if profiles:
    # Find a star player
    for player_id, profile in profiles.items():
        if profile.get('position') == 'QB' and profile.get('passing_yards_total', 0) > 500:
            print('\n📋 Example Player Profile:')
            print('=' * 60)
            print(f\"Name: {profile.get('player_display_name')}\")
            print(f\"Position: {profile.get('position')}\")
            print(f\"Team: {profile.get('recent_team')}\")
            print(f\"Games Played: {profile.get('games_played')}\")
            
            print('\nSeason Totals:')
            if profile.get('passing_yards_total'):
                print(f\"  Passing Yards: {profile.get('passing_yards_total', 0):.0f}\")
                print(f\"  Passing TDs: {profile.get('passing_tds_total', 0):.0f}\")
                print(f\"  Passing EPA Total: {profile.get('passing_epa_total', 0):.2f}\")
            
            print('\nPer Game Averages:')
            if profile.get('passing_yards_per_game'):
                print(f\"  Passing Yards/Game: {profile.get('passing_yards_per_game', 0):.1f}\")
                print(f\"  Passing TDs/Game: {profile.get('passing_tds_per_game', 0):.1f}\")
            
            print('\nAdvanced Metrics:')
            if profile.get('dakota_avg'):
                print(f\"  DAKOTA Average: {profile.get('dakota_avg', 0):.2f}\")
            if profile.get('pacr_avg'):
                print(f\"  PACR Average: {profile.get('pacr_avg', 0):.2f}\")
            
            break
"

echo ""
echo "4. Testing position rankings with various metrics..."
docker exec nflpred-api python3 -c "
import sys
sys.path.insert(0, '/app')
from api.adapters.nflverse_r_adapter import NFLverseRAdapter

adapter = NFLverseRAdapter()

# Get QB rankings by different metrics
print('🏈 QB Rankings by EPA (2025 Season):')
rankings = adapter.get_position_rankings(2025, None, 'QB', 'passing_epa')
if not rankings.empty:
    for _, player in rankings.head(5).iterrows():
        print(f\"  {player['rank']:2}. {player['player_display_name']:20} ({player['team']}) - EPA: {player['passing_epa']:.1f}\")

print('\n🏃 RB Rankings by Fantasy Points PPR (2025 Season):')
rankings = adapter.get_position_rankings(2025, None, 'RB', 'fantasy_points_ppr')
if not rankings.empty:
    for _, player in rankings.head(5).iterrows():
        print(f\"  {player['rank']:2}. {player['player_display_name']:20} ({player['team']}) - PPR: {player['fantasy_points_ppr']:.1f}\")
"

echo ""
echo "5. Creating API endpoint for player stats..."
cat > /tmp/player_stats_route.py << 'EOF'
"""
Add this to your api/routes/predictions.py or create a new route file
"""

@router.get("/player-stats/comprehensive")
async def get_comprehensive_player_stats(
    season: int = Query(..., description="Season year"),
    week: Optional[int] = Query(None, description="Week number"),
    position: Optional[str] = Query(None, description="Position filter"),
    team: Optional[str] = Query(None, description="Team filter"),
    metric: str = Query("fantasy_points_ppr", description="Metric to sort by"),
    limit: int = Query(20, description="Number of results"),
    db: Session = Depends(get_db)
):
    """Get comprehensive player statistics with all available metrics."""
    try:
        adapter = ProviderRegistry.get_adapter("nflverse_r")
        
        # Get comprehensive stats
        df = adapter.get_comprehensive_player_stats(season, week)
        
        if df.empty:
            return {"message": "No stats available", "players": []}
        
        # Apply filters
        if position:
            df = df[df['position'] == position]
        if team:
            df = df[df['recent_team'] == team]
        
        # Sort by metric if it exists
        if metric in df.columns:
            df = df.nlargest(limit, metric, keep='all')
        else:
            df = df.head(limit)
        
        # Convert to dict and clean NaN values
        players = df.to_dict('records')
        for player in players:
            for key, value in player.items():
                if pd.isna(value):
                    player[key] = None
        
        return {
            "season": season,
            "week": week,
            "total_columns": len(df.columns),
            "count": len(players),
            "players": players
        }
        
    except Exception as e:
        logger.error(f"Error getting comprehensive player stats: {e}")
        raise HTTPException(status_code=500, detail=str(e))
EOF

echo -e "${GREEN}✅ API endpoint template created at /tmp/player_stats_route.py${NC}"

echo ""
echo "=========================================="
echo "✨ COMPREHENSIVE PLAYER STATS READY!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Add the enhanced methods to your nflverse_r_adapter.py"
echo "2. Add the new API endpoint to your routes"
echo "3. Update your frontend to display player profiles"
echo "4. Consider adding player comparison features"
echo ""
echo "Available data includes:"
echo "- All passing stats (yards, TDs, EPA, DAKOTA, etc.)"
echo "- All rushing stats (yards, TDs, fumbles, etc.)"
echo "- All receiving stats (targets, receptions, RACR, WOPR, etc.)"
echo "- Fantasy points (standard and PPR)"
echo "- Advanced efficiency metrics"
echo "- Game-by-game logs"
echo "- Season aggregations"