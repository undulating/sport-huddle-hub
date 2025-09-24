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
