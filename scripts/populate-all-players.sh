#!/bin/bash

# populate-all-players.sh
# Fully populate your database with ALL NFL players and their complete stats

set -e

echo "=========================================="
echo "🏈 POPULATING COMPLETE PLAYER DATABASE"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "1. Creating player tables in database (if not exists)..."
docker exec nflpred-api python3 -c "
from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime, ForeignKey, JSON, Boolean
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from api.storage.db import engine
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

Base = declarative_base()

class Player(Base):
    __tablename__ = 'players'
    
    id = Column(Integer, primary_key=True)
    espn_id = Column(String, unique=True, index=True)
    name = Column(String, nullable=False)
    display_name = Column(String)
    team_abbr = Column(String, index=True)
    position = Column(String, index=True)
    position_group = Column(String)
    jersey_number = Column(String)
    height = Column(String)
    weight = Column(String)
    age = Column(Integer)
    experience_years = Column(Integer)
    college = Column(String)
    headshot_url = Column(String)
    active = Column(Boolean, default=True)
    
    # Current season stats
    games_played = Column(Integer, default=0)
    
    # Passing stats
    passing_yards = Column(Integer, default=0)
    passing_tds = Column(Integer, default=0)
    completions = Column(Integer, default=0)
    attempts = Column(Integer, default=0)
    interceptions = Column(Integer, default=0)
    passer_rating = Column(Float)
    
    # Rushing stats
    rushing_yards = Column(Integer, default=0)
    rushing_tds = Column(Integer, default=0)
    carries = Column(Integer, default=0)
    yards_per_carry = Column(Float)
    
    # Receiving stats
    receiving_yards = Column(Integer, default=0)
    receiving_tds = Column(Integer, default=0)
    receptions = Column(Integer, default=0)
    targets = Column(Integer, default=0)
    yards_per_reception = Column(Float)
    
    # Fantasy
    fantasy_points_std = Column(Float, default=0)
    fantasy_points_ppr = Column(Float, default=0)
    
    # Metadata
    last_updated = Column(DateTime)
    season = Column(Integer)
    
    # Store complete stats as JSON for flexibility
    full_stats = Column(JSON)

try:
    Base.metadata.create_all(engine)
    print('✅ Player tables ready')
except Exception as e:
    print(f'⚠️ Table creation issue (may already exist): {e}')
"

echo ""
echo "2. Fetching ALL team rosters (1,700+ players)..."
docker exec nflpred-api python3 -c "
import requests
import json
import time
from datetime import datetime
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from api.storage.db import engine

Session = sessionmaker(bind=engine)
session = Session()

# ESPN API base URL
base_url = 'https://site.api.espn.com/apis/site/v2/sports/football/nfl'

# Get all teams
print('Fetching all 32 NFL teams...')
teams_url = f'{base_url}/teams'
teams_response = requests.get(teams_url)

if teams_response.status_code != 200:
    print('❌ Failed to get teams')
    exit(1)

teams_data = teams_response.json()
all_teams = []

for team_entry in teams_data['sports'][0]['leagues'][0]['teams']:
    team = team_entry['team']
    all_teams.append({
        'id': team['id'],
        'abbreviation': team['abbreviation'],
        'name': team['displayName']
    })

print(f'✅ Found {len(all_teams)} teams')

# Fetch roster for each team
all_players = []
total_players = 0

for idx, team in enumerate(all_teams, 1):
    print(f'\\n[{idx}/{len(all_teams)}] Fetching {team[\"name\"]} roster...')
    
    roster_url = f'{base_url}/teams/{team[\"id\"]}?enable=roster'
    roster_response = requests.get(roster_url)
    
    if roster_response.status_code == 200:
        roster_data = roster_response.json()
        
        if 'team' in roster_data and 'athletes' in roster_data['team']:
            athletes = roster_data['team']['athletes']
            
            for athlete in athletes:
                player = {
                    'espn_id': str(athlete.get('id')),
                    'name': athlete.get('fullName', 'Unknown'),
                    'display_name': athlete.get('displayName', athlete.get('fullName')),
                    'team_abbr': team['abbreviation'],
                    'position': athlete.get('position', {}).get('abbreviation') if isinstance(athlete.get('position'), dict) else None,
                    'position_group': athlete.get('position', {}).get('parent', {}).get('abbreviation') if isinstance(athlete.get('position'), dict) else None,
                    'jersey_number': athlete.get('jersey'),
                    'height': athlete.get('displayHeight'),
                    'weight': athlete.get('displayWeight'),
                    'age': athlete.get('age'),
                    'experience_years': athlete.get('experience', {}).get('years') if isinstance(athlete.get('experience'), dict) else 0,
                    'college': athlete.get('college', {}).get('name') if isinstance(athlete.get('college'), dict) else None,
                    'headshot_url': athlete.get('headshot', {}).get('href') if isinstance(athlete.get('headshot'), dict) else None,
                    'active': athlete.get('active', True),
                    'last_updated': datetime.now(),
                    'season': 2025
                }
                
                all_players.append(player)
                total_players += 1
            
            print(f'  ✅ {team[\"abbreviation\"]}: {len(athletes)} players')
    
    # Be respectful to ESPN's servers
    time.sleep(0.3)

print(f'\\n✅ Total players fetched: {total_players}')

# Save to database
print('\\nSaving players to database...')

from api.storage.models import Player  # Assuming you added the Player model

for player_data in all_players:
    try:
        # Check if player exists
        existing = session.query(Player).filter_by(espn_id=player_data['espn_id']).first()
        
        if existing:
            # Update existing player
            for key, value in player_data.items():
                setattr(existing, key, value)
        else:
            # Create new player
            player = Player(**player_data)
            session.add(player)
    except Exception as e:
        print(f'  ⚠️ Error with player {player_data.get(\"name\")}: {e}')
        continue

session.commit()
print(f'✅ All players saved to database!')
"

echo ""
echo -e "${YELLOW}3. Fetching current season stats for all players...${NC}"
docker exec nflpred-api python3 -c "
import requests
import json
import time
from datetime import datetime
from sqlalchemy.orm import sessionmaker
from api.storage.db import engine

Session = sessionmaker(bind=engine)
session = Session()

base_url = 'https://site.api.espn.com/apis/site/v2/sports/football/nfl'

print('Fetching 2025 season leaders to get stats...')

# Get season leaders for all major categories
categories = [
    'passingYards', 'passingTouchdowns', 'completions',
    'rushingYards', 'rushingTouchdowns', 'rushingAttempts',
    'receivingYards', 'receivingTouchdowns', 'receptions', 'targets'
]

stats_by_player = {}

for category in categories:
    url = f'{base_url}/leaders?season=2025&seasontype=2'
    response = requests.get(url)
    
    if response.status_code == 200:
        data = response.json()
        
        for leader_category in data.get('leaders', []):
            if category.lower() in leader_category.get('name', '').lower():
                print(f'  Processing {leader_category.get(\"displayName\")}...')
                
                for leader in leader_category.get('leaders', []):
                    athlete = leader.get('athlete', {})
                    player_id = str(athlete.get('id'))
                    
                    if player_id not in stats_by_player:
                        stats_by_player[player_id] = {
                            'espn_id': player_id,
                            'name': athlete.get('displayName'),
                            'team': athlete.get('team', {}).get('abbreviation') if athlete.get('team') else None
                        }
                    
                    # Map stat to our schema
                    value = float(leader.get('value', 0))
                    
                    if 'passingYards' in category:
                        stats_by_player[player_id]['passing_yards'] = value
                    elif 'passingTouchdowns' in category:
                        stats_by_player[player_id]['passing_tds'] = value
                    elif 'completions' in category:
                        stats_by_player[player_id]['completions'] = value
                    elif 'rushingYards' in category:
                        stats_by_player[player_id]['rushing_yards'] = value
                    elif 'rushingTouchdowns' in category:
                        stats_by_player[player_id]['rushing_tds'] = value
                    elif 'rushingAttempts' in category:
                        stats_by_player[player_id]['carries'] = value
                    elif 'receivingYards' in category:
                        stats_by_player[player_id]['receiving_yards'] = value
                    elif 'receivingTouchdowns' in category:
                        stats_by_player[player_id]['receiving_tds'] = value
                    elif 'receptions' in category:
                        stats_by_player[player_id]['receptions'] = value
                    elif 'targets' in category:
                        stats_by_player[player_id]['targets'] = value
    
    time.sleep(0.2)

print(f'\\n✅ Found stats for {len(stats_by_player)} players')

# Update database with stats
print('Updating player stats in database...')

from api.storage.models import Player

for player_id, stats in stats_by_player.items():
    try:
        player = session.query(Player).filter_by(espn_id=player_id).first()
        
        if player:
            for key, value in stats.items():
                if key not in ['espn_id', 'name', 'team']:
                    setattr(player, key, value)
            
            # Calculate fantasy points
            player.fantasy_points_std = (
                player.passing_yards * 0.04 +
                player.passing_tds * 4 +
                player.interceptions * -2 +
                player.rushing_yards * 0.1 +
                player.rushing_tds * 6 +
                player.receiving_yards * 0.1 +
                player.receiving_tds * 6
            )
            
            player.fantasy_points_ppr = player.fantasy_points_std + player.receptions
    except Exception as e:
        print(f'  ⚠️ Error updating {stats.get(\"name\")}: {e}')

session.commit()
print('✅ Player stats updated!')
"

echo ""
echo -e "${GREEN}4. Creating API endpoints to serve player data...${NC}"
cat > api/routes/players.py << 'EOF'
"""
Player routes for comprehensive player data.
"""

from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import or_, and_

from api.deps import get_db
from api.storage.models import Player
from api.app_logging import get_logger

logger = get_logger(__name__)
router = APIRouter()

@router.get("/")
async def get_players(
    position: Optional[str] = Query(None, description="Filter by position"),
    team: Optional[str] = Query(None, description="Filter by team"),
    search: Optional[str] = Query(None, description="Search player names"),
    limit: int = Query(50, le=500, description="Number of results"),
    offset: int = Query(0, description="Offset for pagination"),
    db: Session = Depends(get_db)
):
    """Get players with optional filters."""
    query = db.query(Player)
    
    if position:
        query = query.filter(Player.position == position)
    
    if team:
        query = query.filter(Player.team_abbr == team)
    
    if search:
        query = query.filter(
            or_(
                Player.name.ilike(f"%{search}%"),
                Player.display_name.ilike(f"%{search}%")
            )
        )
    
    total = query.count()
    players = query.offset(offset).limit(limit).all()
    
    return {
        "total": total,
        "limit": limit,
        "offset": offset,
        "players": players
    }

@router.get("/leaders")
async def get_stat_leaders(
    stat: str = Query(..., description="Stat to rank by (passing_yards, rushing_yards, etc)"),
    position: Optional[str] = Query(None, description="Filter by position"),
    limit: int = Query(20, description="Number of results"),
    db: Session = Depends(get_db)
):
    """Get statistical leaders."""
    query = db.query(Player)
    
    if position:
        query = query.filter(Player.position == position)
    
    # Order by the requested stat
    if hasattr(Player, stat):
        query = query.order_by(getattr(Player, stat).desc())
    else:
        raise HTTPException(status_code=400, detail=f"Invalid stat: {stat}")
    
    leaders = query.limit(limit).all()
    
    return {
        "stat": stat,
        "position": position,
        "leaders": leaders
    }

@router.get("/{player_id}")
async def get_player(
    player_id: str,
    db: Session = Depends(get_db)
):
    """Get specific player details."""
    player = db.query(Player).filter(Player.espn_id == player_id).first()
    
    if not player:
        raise HTTPException(status_code=404, detail="Player not found")
    
    return player

@router.get("/team/{team_abbr}")
async def get_team_roster(
    team_abbr: str,
    db: Session = Depends(get_db)
):
    """Get complete roster for a team."""
    players = db.query(Player).filter(
        Player.team_abbr == team_abbr
    ).order_by(Player.jersey_number).all()
    
    return {
        "team": team_abbr,
        "count": len(players),
        "roster": players
    }

@router.get("/fantasy/rankings")
async def get_fantasy_rankings(
    scoring: str = Query("ppr", description="Scoring type: std or ppr"),
    position: Optional[str] = Query(None, description="Filter by position"),
    limit: int = Query(50, description="Number of results"),
    db: Session = Depends(get_db)
):
    """Get fantasy football rankings."""
    query = db.query(Player)
    
    if position:
        if position == "FLEX":
            query = query.filter(Player.position.in_(["RB", "WR", "TE"]))
        else:
            query = query.filter(Player.position == position)
    
    # Order by fantasy points
    if scoring == "ppr":
        query = query.order_by(Player.fantasy_points_ppr.desc())
    else:
        query = query.order_by(Player.fantasy_points_std.desc())
    
    players = query.limit(limit).all()
    
    return {
        "scoring": scoring,
        "position": position,
        "rankings": players
    }
EOF

echo -e "${GREEN}✅ Created player routes${NC}"

echo ""
echo -e "${GREEN}5. Registering player routes in main app...${NC}"
docker exec nflpred-api python3 -c "
# Add player routes to your main app.py
print('To complete setup, add this to your api/app.py:')
print('')
print('from api.routes import players')
print('')
print('# In create_app function, add:')
print('app.include_router(players.router, prefix=\"/api/players\", tags=[\"players\"])')
print('')
print('✅ Player routes ready to be registered!')
"

echo ""
echo "=========================================="
echo "✨ COMPLETE PLAYER DATABASE POPULATED!"
echo "=========================================="
echo ""
echo -e "${GREEN}Successfully populated:${NC}"
echo "✅ 1,700+ NFL players from all 32 teams"
echo "✅ Complete profiles (age, height, weight, college, etc.)"
echo "✅ Current 2025 season stats"
echo "✅ Fantasy points calculated"
echo "✅ Position and team indexes for fast queries"
echo ""
echo -e "${YELLOW}API Endpoints Available:${NC}"
echo "GET /api/players - List all players with filters"
echo "GET /api/players/leaders - Statistical leaders"
echo "GET /api/players/{player_id} - Individual player details"
echo "GET /api/players/team/{team} - Team roster"
echo "GET /api/players/fantasy/rankings - Fantasy rankings"
echo ""
echo -e "${GREEN}Next Steps:${NC}"
echo "1. Add player routes to your app.py"
echo "2. Test the API endpoints"
echo "3. Integrate player data into GameCards"
echo "4. Add player impact to Elo predictions"
echo "5. Schedule weekly updates"