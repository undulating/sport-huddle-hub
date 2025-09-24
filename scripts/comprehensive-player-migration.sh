#!/bin/bash
# comprehensive-player-migration.sh
# Complete migration and ingestion for normalized player database

echo "=========================================="
echo "🏈 COMPREHENSIVE PLAYER DATA MIGRATION"
echo "=========================================="

# Step 1: Create Alembic migration file
echo "1. Creating Alembic migration for normalized player tables..."
cat > api/storage/migrations/versions/normalize_player_tables.py << 'EOF'
"""Normalize player tables - add player_games and player_season_totals

Revision ID: normalize_player_tables
Revises: 
Create Date: 2025-09-22
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers
revision = 'normalize_player_tables'
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    # First, enhance the existing players table
    print("Enhancing players table...")
    
    # Add new columns to players table if they don't exist
    op.add_column('players', sa.Column('player_id', sa.String(50), nullable=True))
    op.add_column('players', sa.Column('first_name', sa.String(100), nullable=True))
    op.add_column('players', sa.Column('last_name', sa.String(100), nullable=True))
    op.add_column('players', sa.Column('birth_date', sa.DateTime(), nullable=True))
    op.add_column('players', sa.Column('draft_year', sa.Integer(), nullable=True))
    op.add_column('players', sa.Column('draft_round', sa.Integer(), nullable=True))
    op.add_column('players', sa.Column('draft_pick', sa.Integer(), nullable=True))
    op.add_column('players', sa.Column('draft_team', sa.String(10), nullable=True))
    op.add_column('players', sa.Column('status', sa.String(20), nullable=True))
    op.add_column('players', sa.Column('yahoo_id', sa.String(50), nullable=True))
    
    # Create unique constraint on player_id
    op.create_unique_constraint('uq_players_player_id', 'players', ['player_id'])
    op.create_index('idx_players_player_id', 'players', ['player_id'])
    
    # Create player_games table for individual game stats
    print("Creating player_games table...")
    op.create_table('player_games',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('player_id', sa.String(50), nullable=False),
        sa.Column('game_id', sa.Integer(), nullable=False),
        sa.Column('team_id', sa.Integer(), nullable=False),
        sa.Column('season', sa.Integer(), nullable=False),
        sa.Column('week', sa.Integer(), nullable=False),
        sa.Column('game_date', sa.DateTime(), nullable=False),
        sa.Column('opponent_team_id', sa.Integer(), nullable=True),
        sa.Column('home_or_away', sa.String(4), nullable=True),
        
        # Player status
        sa.Column('position_played', sa.String(10), nullable=True),
        sa.Column('snap_count', sa.Integer(), nullable=True),
        sa.Column('snap_percentage', sa.Float(), nullable=True),
        sa.Column('started', sa.Boolean(), default=False),
        
        # Passing stats
        sa.Column('completions', sa.Integer(), nullable=True),
        sa.Column('attempts', sa.Integer(), nullable=True),
        sa.Column('passing_yards', sa.Integer(), nullable=True),
        sa.Column('passing_tds', sa.Integer(), nullable=True),
        sa.Column('interceptions', sa.Integer(), nullable=True),
        sa.Column('sacks', sa.Integer(), nullable=True),
        sa.Column('sack_yards', sa.Integer(), nullable=True),
        sa.Column('sack_fumbles', sa.Integer(), nullable=True),
        sa.Column('sack_fumbles_lost', sa.Integer(), nullable=True),
        sa.Column('passing_air_yards', sa.Integer(), nullable=True),
        sa.Column('passing_yards_after_catch', sa.Integer(), nullable=True),
        sa.Column('passing_first_downs', sa.Integer(), nullable=True),
        sa.Column('passing_epa', sa.Float(), nullable=True),
        sa.Column('passing_2pt_conversions', sa.Integer(), nullable=True),
        sa.Column('pacr', sa.Float(), nullable=True),
        sa.Column('dakota', sa.Float(), nullable=True),
        
        # Rushing stats
        sa.Column('carries', sa.Integer(), nullable=True),
        sa.Column('rushing_yards', sa.Integer(), nullable=True),
        sa.Column('rushing_tds', sa.Integer(), nullable=True),
        sa.Column('rushing_fumbles', sa.Integer(), nullable=True),
        sa.Column('rushing_fumbles_lost', sa.Integer(), nullable=True),
        sa.Column('rushing_first_downs', sa.Integer(), nullable=True),
        sa.Column('rushing_epa', sa.Float(), nullable=True),
        sa.Column('rushing_2pt_conversions', sa.Integer(), nullable=True),
        sa.Column('racr', sa.Float(), nullable=True),
        
        # Receiving stats
        sa.Column('targets', sa.Integer(), nullable=True),
        sa.Column('receptions', sa.Integer(), nullable=True),
        sa.Column('receiving_yards', sa.Integer(), nullable=True),
        sa.Column('receiving_tds', sa.Integer(), nullable=True),
        sa.Column('receiving_fumbles', sa.Integer(), nullable=True),
        sa.Column('receiving_fumbles_lost', sa.Integer(), nullable=True),
        sa.Column('receiving_air_yards', sa.Integer(), nullable=True),
        sa.Column('receiving_yards_after_catch', sa.Integer(), nullable=True),
        sa.Column('receiving_first_downs', sa.Integer(), nullable=True),
        sa.Column('receiving_epa', sa.Float(), nullable=True),
        sa.Column('receiving_2pt_conversions', sa.Integer(), nullable=True),
        sa.Column('target_share', sa.Float(), nullable=True),
        sa.Column('air_yards_share', sa.Float(), nullable=True),
        sa.Column('wopr', sa.Float(), nullable=True),
        
        # Special teams
        sa.Column('special_teams_tds', sa.Integer(), nullable=True),
        
        # Fantasy
        sa.Column('fantasy_points', sa.Float(), nullable=True),
        sa.Column('fantasy_points_ppr', sa.Float(), nullable=True),
        
        # Additional stats as JSON
        sa.Column('additional_stats', postgresql.JSON(astext_type=sa.Text()), nullable=True),
        
        # Timestamps
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['game_id'], ['games.id']),
        sa.ForeignKeyConstraint(['team_id'], ['teams.id']),
        sa.ForeignKeyConstraint(['opponent_team_id'], ['teams.id']),
        sa.UniqueConstraint('player_id', 'game_id', name='unique_player_game')
    )
    
    # Create indexes for player_games
    op.create_index('idx_player_game_player', 'player_games', ['player_id'])
    op.create_index('idx_player_game_game', 'player_games', ['game_id'])
    op.create_index('idx_player_game_date', 'player_games', ['game_date'])
    op.create_index('idx_player_game_week', 'player_games', ['season', 'week'])
    op.create_index('idx_player_game_fantasy', 'player_games', ['fantasy_points_ppr'])
    
    # Create player_season_totals table
    print("Creating player_season_totals table...")
    op.create_table('player_season_totals',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('player_id', sa.String(50), nullable=False),
        sa.Column('team_id', sa.Integer(), nullable=True),
        sa.Column('season', sa.Integer(), nullable=False),
        sa.Column('season_type', sa.String(20), default='regular'),
        
        # Games
        sa.Column('games_played', sa.Integer(), default=0),
        sa.Column('games_started', sa.Integer(), default=0),
        sa.Column('position', sa.String(10), nullable=True),
        
        # Season totals - Passing
        sa.Column('completions_total', sa.Integer(), default=0),
        sa.Column('attempts_total', sa.Integer(), default=0),
        sa.Column('passing_yards_total', sa.Integer(), default=0),
        sa.Column('passing_tds_total', sa.Integer(), default=0),
        sa.Column('interceptions_total', sa.Integer(), default=0),
        sa.Column('sacks_total', sa.Integer(), default=0),
        sa.Column('sack_yards_total', sa.Integer(), default=0),
        sa.Column('passing_epa_total', sa.Float(), default=0),
        sa.Column('passing_air_yards_total', sa.Integer(), default=0),
        sa.Column('passing_yards_after_catch_total', sa.Integer(), default=0),
        sa.Column('passing_first_downs_total', sa.Integer(), default=0),
        
        # Season totals - Rushing
        sa.Column('carries_total', sa.Integer(), default=0),
        sa.Column('rushing_yards_total', sa.Integer(), default=0),
        sa.Column('rushing_tds_total', sa.Integer(), default=0),
        sa.Column('rushing_fumbles_total', sa.Integer(), default=0),
        sa.Column('rushing_fumbles_lost_total', sa.Integer(), default=0),
        sa.Column('rushing_first_downs_total', sa.Integer(), default=0),
        sa.Column('rushing_epa_total', sa.Float(), default=0),
        
        # Season totals - Receiving
        sa.Column('targets_total', sa.Integer(), default=0),
        sa.Column('receptions_total', sa.Integer(), default=0),
        sa.Column('receiving_yards_total', sa.Integer(), default=0),
        sa.Column('receiving_tds_total', sa.Integer(), default=0),
        sa.Column('receiving_fumbles_total', sa.Integer(), default=0),
        sa.Column('receiving_fumbles_lost_total', sa.Integer(), default=0),
        sa.Column('receiving_air_yards_total', sa.Integer(), default=0),
        sa.Column('receiving_yards_after_catch_total', sa.Integer(), default=0),
        sa.Column('receiving_first_downs_total', sa.Integer(), default=0),
        sa.Column('receiving_epa_total', sa.Float(), default=0),
        
        # Fantasy totals
        sa.Column('fantasy_points_total', sa.Float(), default=0),
        sa.Column('fantasy_points_ppr_total', sa.Float(), default=0),
        
        # Season averages
        sa.Column('passing_yards_per_game', sa.Float(), nullable=True),
        sa.Column('rushing_yards_per_game', sa.Float(), nullable=True),
        sa.Column('receiving_yards_per_game', sa.Float(), nullable=True),
        sa.Column('fantasy_points_per_game', sa.Float(), nullable=True),
        sa.Column('fantasy_points_ppr_per_game', sa.Float(), nullable=True),
        
        # Efficiency metrics
        sa.Column('completion_percentage', sa.Float(), nullable=True),
        sa.Column('yards_per_attempt', sa.Float(), nullable=True),
        sa.Column('yards_per_carry', sa.Float(), nullable=True),
        sa.Column('yards_per_reception', sa.Float(), nullable=True),
        sa.Column('passer_rating', sa.Float(), nullable=True),
        sa.Column('qbr', sa.Float(), nullable=True),
        
        # Advanced metrics
        sa.Column('pacr_avg', sa.Float(), nullable=True),
        sa.Column('racr_avg', sa.Float(), nullable=True),
        sa.Column('target_share_avg', sa.Float(), nullable=True),
        sa.Column('air_yards_share_avg', sa.Float(), nullable=True),
        sa.Column('wopr_avg', sa.Float(), nullable=True),
        sa.Column('dakota_avg', sa.Float(), nullable=True),
        
        # Timestamps
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['team_id'], ['teams.id']),
        sa.UniqueConstraint('player_id', 'season', 'season_type', name='unique_player_season')
    )
    
    # Create indexes for season totals
    op.create_index('idx_player_season', 'player_season_totals', ['player_id', 'season'])
    op.create_index('idx_season_fantasy', 'player_season_totals', ['season', 'fantasy_points_ppr_total'])
    op.create_index('idx_season_position', 'player_season_totals', ['season', 'position'])
    
    print("Migration complete!")


def downgrade():
    op.drop_table('player_season_totals')
    op.drop_table('player_games')
    
    # Remove added columns from players table
    op.drop_constraint('uq_players_player_id', 'players', type_='unique')
    op.drop_column('players', 'player_id')
    op.drop_column('players', 'first_name')
    op.drop_column('players', 'last_name')
    op.drop_column('players', 'birth_date')
    op.drop_column('players', 'draft_year')
    op.drop_column('players', 'draft_round')
    op.drop_column('players', 'draft_pick')
    op.drop_column('players', 'draft_team')
    op.drop_column('players', 'status')
    op.drop_column('players', 'yahoo_id')
EOF

echo "✅ Migration file created"

# Step 2: Run the migration
echo ""
echo "2. Running database migration..."
docker exec nflpred-api alembic upgrade head

# Step 3: Create ingestion script
echo ""
echo "3. Creating player data ingestion script..."
cat > api/scripts/ingest_player_data.py << 'EOF'
"""
Ingest comprehensive player data from NFLverse into normalized tables.
"""
import pandas as pd
import numpy as np
from datetime import datetime
from sqlalchemy.orm import Session
from api.storage.db import get_db_context
from api.storage.models import Player, Game, Team
from api.adapters.nflverse_r_adapter import NFLverseRAdapter
from api.app_logging import get_logger

logger = get_logger(__name__)

def ingest_player_games(season: int, week: int = None):
    """Ingest player game-level stats."""
    
    with get_db_context() as db:
        adapter = NFLverseRAdapter()
        
        # Get comprehensive player stats
        logger.info(f"Fetching player stats for season {season}, week {week}")
        df = adapter.get_comprehensive_player_stats(season, week)
        
        if df.empty:
            logger.warning("No player data found")
            return
        
        logger.info(f"Processing {len(df)} player game records")
        
        # Process each row
        for _, row in df.iterrows():
            player_id = row.get('player_id')
            if not player_id:
                continue
            
            # Get or create player
            player = db.query(Player).filter(Player.player_id == player_id).first()
            if not player:
                player = Player(
                    player_id=player_id,
                    name=row.get('player_name', ''),
                    display_name=row.get('player_display_name', ''),
                    position=row.get('position'),
                    position_group=row.get('position_group'),
                    team_abbr=row.get('recent_team'),
                    headshot_url=row.get('headshot_url'),
                    active=True,
                    season=season
                )
                db.add(player)
                db.flush()
            
            # Find the game
            game = db.query(Game).filter(
                Game.season == season,
                Game.week == row.get('week'),
                db.or_(
                    Game.home_team.has(abbreviation=row.get('recent_team')),
                    Game.away_team.has(abbreviation=row.get('opponent_team'))
                )
            ).first()
            
            if not game:
                logger.warning(f"Game not found for {player_id} week {row.get('week')}")
                continue
            
            # Get team IDs
            team = db.query(Team).filter(Team.abbreviation == row.get('recent_team')).first()
            opponent = db.query(Team).filter(Team.abbreviation == row.get('opponent_team')).first()
            
            if not team:
                continue
            
            # Check if player_game already exists
            from sqlalchemy import text
            existing = db.execute(text("""
                SELECT id FROM player_games 
                WHERE player_id = :player_id AND game_id = :game_id
            """), {"player_id": player_id, "game_id": game.id}).first()
            
            if existing:
                # Update existing record
                db.execute(text("""
                    UPDATE player_games SET
                        completions = :completions,
                        attempts = :attempts,
                        passing_yards = :passing_yards,
                        passing_tds = :passing_tds,
                        interceptions = :interceptions,
                        carries = :carries,
                        rushing_yards = :rushing_yards,
                        rushing_tds = :rushing_tds,
                        targets = :targets,
                        receptions = :receptions,
                        receiving_yards = :receiving_yards,
                        receiving_tds = :receiving_tds,
                        fantasy_points = :fantasy_points,
                        fantasy_points_ppr = :fantasy_points_ppr,
                        updated_at = :updated_at
                    WHERE id = :id
                """), {
                    "id": existing[0],
                    "completions": row.get('completions'),
                    "attempts": row.get('attempts'),
                    "passing_yards": row.get('passing_yards'),
                    "passing_tds": row.get('passing_tds'),
                    "interceptions": row.get('interceptions'),
                    "carries": row.get('carries'),
                    "rushing_yards": row.get('rushing_yards'),
                    "rushing_tds": row.get('rushing_tds'),
                    "targets": row.get('targets'),
                    "receptions": row.get('receptions'),
                    "receiving_yards": row.get('receiving_yards'),
                    "receiving_tds": row.get('receiving_tds'),
                    "fantasy_points": row.get('fantasy_points'),
                    "fantasy_points_ppr": row.get('fantasy_points_ppr'),
                    "updated_at": datetime.utcnow()
                })
            else:
                # Insert new record
                home_or_away = 'home' if game.home_team_id == team.id else 'away'
                
                db.execute(text("""
                    INSERT INTO player_games (
                        player_id, game_id, team_id, season, week, game_date,
                        opponent_team_id, home_or_away, position_played,
                        completions, attempts, passing_yards, passing_tds, interceptions,
                        carries, rushing_yards, rushing_tds,
                        targets, receptions, receiving_yards, receiving_tds,
                        fantasy_points, fantasy_points_ppr,
                        passing_epa, rushing_epa, receiving_epa,
                        passing_air_yards, receiving_air_yards,
                        target_share, air_yards_share, wopr, pacr, racr, dakota,
                        created_at, updated_at
                    ) VALUES (
                        :player_id, :game_id, :team_id, :season, :week, :game_date,
                        :opponent_team_id, :home_or_away, :position_played,
                        :completions, :attempts, :passing_yards, :passing_tds, :interceptions,
                        :carries, :rushing_yards, :rushing_tds,
                        :targets, :receptions, :receiving_yards, :receiving_tds,
                        :fantasy_points, :fantasy_points_ppr,
                        :passing_epa, :rushing_epa, :receiving_epa,
                        :passing_air_yards, :receiving_air_yards,
                        :target_share, :air_yards_share, :wopr, :pacr, :racr, :dakota,
                        :created_at, :updated_at
                    )
                """), {
                    "player_id": player_id,
                    "game_id": game.id,
                    "team_id": team.id,
                    "season": season,
                    "week": row.get('week'),
                    "game_date": game.game_date,
                    "opponent_team_id": opponent.id if opponent else None,
                    "home_or_away": home_or_away,
                    "position_played": row.get('position'),
                    "completions": row.get('completions'),
                    "attempts": row.get('attempts'),
                    "passing_yards": row.get('passing_yards'),
                    "passing_tds": row.get('passing_tds'),
                    "interceptions": row.get('interceptions'),
                    "carries": row.get('carries'),
                    "rushing_yards": row.get('rushing_yards'),
                    "rushing_tds": row.get('rushing_tds'),
                    "targets": row.get('targets'),
                    "receptions": row.get('receptions'),
                    "receiving_yards": row.get('receiving_yards'),
                    "receiving_tds": row.get('receiving_tds'),
                    "fantasy_points": row.get('fantasy_points'),
                    "fantasy_points_ppr": row.get('fantasy_points_ppr'),
                    "passing_epa": row.get('passing_epa'),
                    "rushing_epa": row.get('rushing_epa'),
                    "receiving_epa": row.get('receiving_epa'),
                    "passing_air_yards": row.get('passing_air_yards'),
                    "receiving_air_yards": row.get('receiving_air_yards'),
                    "target_share": row.get('target_share'),
                    "air_yards_share": row.get('air_yards_share'),
                    "wopr": row.get('wopr'),
                    "pacr": row.get('pacr'),
                    "racr": row.get('racr'),
                    "dakota": row.get('dakota'),
                    "created_at": datetime.utcnow(),
                    "updated_at": datetime.utcnow()
                })
        
        db.commit()
        logger.info(f"Successfully ingested player data for season {season}")


def calculate_season_totals(season: int):
    """Calculate season totals from player games."""
    
    with get_db_context() as db:
        # Get all unique players who played this season
        from sqlalchemy import text
        
        players = db.execute(text("""
            SELECT DISTINCT player_id 
            FROM player_games 
            WHERE season = :season
        """), {"season": season}).fetchall()
        
        logger.info(f"Calculating season totals for {len(players)} players")
        
        for player_row in players:
            player_id = player_row[0]
            
            # Calculate aggregates
            result = db.execute(text("""
                SELECT 
                    COUNT(*) as games_played,
                    SUM(CASE WHEN started THEN 1 ELSE 0 END) as games_started,
                    MAX(position_played) as position,
                    MAX(team_id) as team_id,
                    SUM(completions) as completions,
                    SUM(attempts) as attempts,
                    SUM(passing_yards) as passing_yards,
                    SUM(passing_tds) as passing_tds,
                    SUM(interceptions) as interceptions,
                    SUM(carries) as carries,
                    SUM(rushing_yards) as rushing_yards,
                    SUM(rushing_tds) as rushing_tds,
                    SUM(targets) as targets,
                    SUM(receptions) as receptions,
                    SUM(receiving_yards) as receiving_yards,
                    SUM(receiving_tds) as receiving_tds,
                    SUM(fantasy_points) as fantasy_points,
                    SUM(fantasy_points_ppr) as fantasy_points_ppr,
                    AVG(pacr) as pacr_avg,
                    AVG(racr) as racr_avg,
                    AVG(target_share) as target_share_avg,
                    AVG(wopr) as wopr_avg
                FROM player_games
                WHERE player_id = :player_id AND season = :season
            """), {"player_id": player_id, "season": season}).first()
            
            # Check if season total exists
            existing = db.execute(text("""
                SELECT id FROM player_season_totals 
                WHERE player_id = :player_id AND season = :season
            """), {"player_id": player_id, "season": season}).first()
            
            if existing:
                # Update existing
                db.execute(text("""
                    UPDATE player_season_totals SET
                        games_played = :games_played,
                        passing_yards_total = :passing_yards,
                        passing_tds_total = :passing_tds,
                        rushing_yards_total = :rushing_yards,
                        rushing_tds_total = :rushing_tds,
                        receiving_yards_total = :receiving_yards,
                        receiving_tds_total = :receiving_tds,
                        fantasy_points_ppr_total = :fantasy_points_ppr,
                        updated_at = :updated_at
                    WHERE id = :id
                """), {
                    "id": existing[0],
                    "games_played": result.games_played,
                    "passing_yards": result.passing_yards or 0,
                    "passing_tds": result.passing_tds or 0,
                    "rushing_yards": result.rushing_yards or 0,
                    "rushing_tds": result.rushing_tds or 0,
                    "receiving_yards": result.receiving_yards or 0,
                    "receiving_tds": result.receiving_tds or 0,
                    "fantasy_points_ppr": result.fantasy_points_ppr or 0,
                    "updated_at": datetime.utcnow()
                })
            else:
                # Insert new
                db.execute(text("""
                    INSERT INTO player_season_totals (
                        player_id, team_id, season, games_played,
                        passing_yards_total, passing_tds_total,
                        rushing_yards_total, rushing_tds_total,
                        receiving_yards_total, receiving_tds_total,
                        fantasy_points_ppr_total,
                        created_at, updated_at
                    ) VALUES (
                        :player_id, :team_id, :season, :games_played,
                        :passing_yards, :passing_tds,
                        :rushing_yards, :rushing_tds,
                        :receiving_yards, :receiving_tds,
                        :fantasy_points_ppr,
                        :created_at, :updated_at
                    )
                """), {
                    "player_id": player_id,
                    "team_id": result.team_id,
                    "season": season,
                    "games_played": result.games_played,
                    "passing_yards": result.passing_yards or 0,
                    "passing_tds": result.passing_tds or 0,
                    "rushing_yards": result.rushing_yards or 0,
                    "rushing_tds": result.rushing_tds or 0,
                    "receiving_yards": result.receiving_yards or 0,
                    "receiving_tds": result.receiving_tds or 0,
                    "fantasy_points_ppr": result.fantasy_points_ppr or 0,
                    "created_at": datetime.utcnow(),
                    "updated_at": datetime.utcnow()
                })
        
        db.commit()
        logger.info(f"Successfully calculated season totals for {season}")


if __name__ == "__main__":
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: python ingest_player_data.py <season> [week]")
        sys.exit(1)
    
    season = int(sys.argv[1])
    week = int(sys.argv[2]) if len(sys.argv) > 2 else None
    
    # Ingest player games
    ingest_player_games(season, week)
    
    # Calculate season totals
    calculate_season_totals(season)
EOF

echo "✅ Ingestion script created"

# Step 4: Run initial data ingestion
echo ""
echo "4. Ingesting 2024 player data..."
docker exec nflpred-api python api/scripts/ingest_player_data.py 2024

echo ""
echo "5. Ingesting 2025 player data (current season)..."
docker exec nflpred-api python api/scripts/ingest_player_data.py 2025

# Step 5: Test the data
echo ""
echo "6. Testing player data..."
docker exec nflpred-api python -c "
from sqlalchemy import text
from api.storage.db import get_db_context

with get_db_context() as db:
    # Check player_games
    game_count = db.execute(text('SELECT COUNT(*) FROM player_games')).scalar()
    print(f'✓ Player games loaded: {game_count} records')
    
    # Check season totals
    season_count = db.execute(text('SELECT COUNT(*) FROM player_season_totals')).scalar()
    print(f'✓ Season totals calculated: {season_count} player-seasons')
    
    # Get top fantasy players
    top_players = db.execute(text('''
        SELECT p.display_name, p.position, p.team_abbr, 
               pst.fantasy_points_ppr_total
        FROM players p
        JOIN player_season_totals pst ON p.player_id = pst.player_id
        WHERE pst.season = 2025
        ORDER BY pst.fantasy_points_ppr_total DESC
        LIMIT 10
    ''')).fetchall()
    
    print('\nTop 10 Fantasy Players (2025):')
    print('=' * 60)
    for player in top_players:
        print(f'{player[0]:25} {player[1]:3} {player[2]:4} {player[3]:8.1f} pts')
"

echo ""
echo "=========================================="
echo "✅ PLAYER DATA MIGRATION COMPLETE!"
echo "=========================================="
echo ""
echo "Database now contains:"
echo "  - Enhanced players table with player_id"
echo "  - player_games table with all game stats"
echo "  - player_season_totals with aggregated stats"
echo ""
echo "To update weekly:"
echo "  docker exec nflpred-api python api/scripts/ingest_player_data.py 2025 <week>"
echo ""
echo "To query player data:"
echo "  - Top QBs: SELECT * FROM player_season_totals WHERE position='QB' ORDER BY passing_yards_total DESC"
echo "  - Game logs: SELECT * FROM player_games WHERE player_id='<id>' ORDER BY game_date"