"""
Player Value Rating System - Quantifies player importance for injury impact.
Location: api/models/player_value_system.py
"""
import pandas as pd
import numpy as np
from typing import Dict, List, Optional
from datetime import datetime, timedelta
import logging

logger = logging.getLogger(__name__)


class PlayerValueSystem:
    """
    Calculate player values based on their statistical contributions.
    This helps quantify the impact of injuries on team performance.
    """
    
    def __init__(self):
        # Position value multipliers (QB most important)
        self.position_multipliers = {
            'QB': 3.0,
            'RB': 1.5,
            'WR': 1.3,
            'TE': 1.1,
            'OT': 1.2,
            'OG': 0.9,
            'C': 1.0,
            'EDGE': 1.4,
            'DT': 1.0,
            'LB': 1.1,
            'CB': 1.2,
            'S': 1.0,
            'K': 0.7,
            'P': 0.5
        }
        
        self.player_values = {}  # Cache of calculated values
        
    def calculate_qb_value(self, stats: pd.Series) -> float:
        """
        Calculate QB value based on passing stats.
        Returns a value 0-100 representing player importance.
        """
        try:
            # Key metrics for QB value
            pass_yards_per_game = stats.get('passing_yards', 0) / max(stats.get('games', 1), 1)
            td_int_ratio = stats.get('passing_tds', 0) / max(stats.get('interceptions', 1), 1)
            completion_pct = stats.get('completions', 0) / max(stats.get('attempts', 1), 1)
            qbr = stats.get('qbr', 50)  # ESPN QBR if available
            
            # Normalize each metric (0-100 scale)
            yards_score = min(pass_yards_per_game / 3, 100)  # 300 yards/game = 100
            td_int_score = min(td_int_ratio * 20, 100)  # 5:1 ratio = 100
            completion_score = completion_pct * 100
            qbr_score = qbr  # Already 0-100
            
            # Weighted average
            value = (
                yards_score * 0.25 +
                td_int_score * 0.25 +
                completion_score * 0.20 +
                qbr_score * 0.30
            )
            
            return min(value, 100)
            
        except Exception as e:
            logger.error(f"Error calculating QB value: {e}")
            return 50  # Default middle value
    
    def calculate_skill_position_value(self, stats: pd.Series, position: str) -> float:
        """
        Calculate value for RB/WR/TE based on touches and production.
        """
        try:
            # Receiving stats
            targets = stats.get('targets', 0)
            receptions = stats.get('receptions', 0)
            rec_yards = stats.get('receiving_yards', 0)
            rec_tds = stats.get('receiving_tds', 0)
            
            # Rushing stats (for RBs)
            carries = stats.get('carries', 0) if position == 'RB' else 0
            rush_yards = stats.get('rushing_yards', 0) if position == 'RB' else 0
            rush_tds = stats.get('rushing_tds', 0) if position == 'RB' else 0
            
            games = max(stats.get('games', 1), 1)
            
            # Total touches and yards
            total_touches = (receptions + carries) / games
            total_yards = (rec_yards + rush_yards) / games
            total_tds = (rec_tds + rush_tds) / games
            
            # Target share (important for WRs)
            target_share = targets / max(stats.get('team_pass_attempts', 200), 1)
            
            # Calculate value
            if position == 'RB':
                value = (
                    min(total_touches / 20, 1) * 40 +  # 20 touches/game = 40 points
                    min(total_yards / 100, 1) * 30 +   # 100 yards/game = 30 points
                    min(total_tds, 1) * 20 +           # 1 TD/game = 20 points
                    target_share * 100 * 10            # Target share bonus
                )
            else:  # WR/TE
                value = (
                    min(receptions / games / 6, 1) * 30 +  # 6 rec/game = 30 points
                    min(rec_yards / games / 80, 1) * 40 +  # 80 yards/game = 40 points
                    target_share * 100 * 30                 # Target share crucial for WRs
                )
            
            return min(value, 100)
            
        except Exception as e:
            logger.error(f"Error calculating {position} value: {e}")
            return 30
    
    def calculate_defensive_value(self, stats: pd.Series, position: str) -> float:
        """
        Calculate defensive player value based on impact stats.
        """
        try:
            games = max(stats.get('games', 1), 1)
            
            # Common defensive stats
            tackles = stats.get('tackles', 0) / games
            sacks = stats.get('sacks', 0) / games
            ints = stats.get('interceptions', 0) / games
            passes_defended = stats.get('passes_defended', 0) / games
            forced_fumbles = stats.get('forced_fumbles', 0) / games
            
            # Position-specific weighting
            if position in ['EDGE', 'DT']:
                # Pass rushers - sacks and pressures matter most
                value = (
                    min(sacks * 2, 1) * 50 +      # 0.5 sacks/game = 50 points
                    min(tackles / 5, 1) * 30 +     # 5 tackles/game = 30 points
                    forced_fumbles * 20            # Bonus for turnovers
                )
            elif position in ['CB', 'S']:
                # DBs - coverage stats matter
                value = (
                    min(ints * 4, 1) * 40 +         # 0.25 INTs/game = 40 points
                    min(passes_defended / 1, 1) * 30 + # 1 PD/game = 30 points
                    min(tackles / 5, 1) * 30        # Tackling still matters
                )
            else:  # LB
                value = (
                    min(tackles / 8, 1) * 40 +     # 8 tackles/game = 40 points
                    min(sacks * 4, 1) * 30 +       # 0.25 sacks/game = 30 points
                    (ints + forced_fumbles) * 30   # Turnovers bonus
                )
            
            return min(value, 100)
            
        except Exception as e:
            logger.error(f"Error calculating defensive value: {e}")
            return 30
    
    def get_player_value(self, player_name: str, position: str, stats: pd.Series) -> float:
        """
        Get overall player value rating (0-100).
        Higher values indicate more impactful players.
        """
        # Check cache
        if player_name in self.player_values:
            return self.player_values[player_name]
        
        # Calculate base value by position
        if position == 'QB':
            base_value = self.calculate_qb_value(stats)
        elif position in ['RB', 'WR', 'TE']:
            base_value = self.calculate_skill_position_value(stats, position)
        elif position in ['EDGE', 'DT', 'LB', 'CB', 'S']:
            base_value = self.calculate_defensive_value(stats, position)
        else:
            base_value = 30  # Default for other positions
        
        # Apply position multiplier
        position_mult = self.position_multipliers.get(position, 1.0)
        final_value = base_value * position_mult
        
        # Cache the result
        self.player_values[player_name] = final_value
        
        return final_value
    
    def calculate_injury_impact(self, player_value: float, injury_status: str) -> float:
        """
        Convert player value and injury status to Elo rating impact.
        
        Returns negative value representing Elo points to subtract.
        """
        status_multipliers = {
            'Out': 1.0,
            'Doubtful': 0.7,
            'Questionable': 0.3,
            'Probable': 0.1,
            'Active': 0.0
        }
        
        multiplier = status_multipliers.get(injury_status, 0.0)
        
        # Scale player value to Elo impact
        # Top QB (value=100) being out = -100 Elo points
        # Average player (value=30) being out = -30 Elo points
        elo_impact = -player_value * multiplier
        
        return elo_impact
    
    def get_team_injury_impact(self, team_injuries: List[Dict]) -> float:
        """
        Calculate total team impact from all injuries.
        
        Args:
            team_injuries: List of dicts with 'player_name', 'position', 'status', 'stats'
        
        Returns:
            Total Elo adjustment (negative value)
        """
        total_impact = 0
        
        for injury in team_injuries:
            player_value = self.get_player_value(
                injury['player_name'],
                injury['position'],
                injury.get('stats', pd.Series())
            )
            
            impact = self.calculate_injury_impact(
                player_value,
                injury['status']
            )
            
            total_impact += impact
            
            if impact < -20:  # Significant injury
                logger.info(
                    f"  {injury['player_name']} ({injury['position']}): "
                    f"Value={player_value:.1f}, Status={injury['status']}, "
                    f"Impact={impact:.1f}"
                )
        
        # Cap total impact at -150 Elo points
        return max(total_impact, -150)


# Integration function
def sync_player_stats_and_values():
    """
    Sync player stats from NFLverse and calculate values.
    Run this weekly to update player importance ratings.
    """
    import pandas as pd
    from api.storage.db import get_db_context
    
    # Load current season stats
    url = 'https://github.com/nflverse/nflverse-data/releases/download/player_stats/player_stats.csv'
    
    print("Loading player stats from NFLverse...")
    df = pd.read_csv(url)
    
    # Filter to current season
    current_season = 2025
    df = df[df['season'] == current_season]
    
    # Group by player to get season totals
    player_stats = df.groupby(['player_id', 'player_name', 'position']).agg({
        'completions': 'sum',
        'attempts': 'sum', 
        'passing_yards': 'sum',
        'passing_tds': 'sum',
        'interceptions': 'sum',
        'carries': 'sum',
        'rushing_yards': 'sum',
        'rushing_tds': 'sum',
        'targets': 'sum',
        'receptions': 'sum',
        'receiving_yards': 'sum',
        'receiving_tds': 'sum',
        'tackles_combined': 'sum',
        'sacks': 'sum',
        'games': 'max'
    }).reset_index()
    
    # Calculate values
    value_system = PlayerValueSystem()
    
    print(f"Calculating values for {len(player_stats)} players...")
    
    player_values = {}
    for _, player in player_stats.iterrows():
        value = value_system.get_player_value(
            player['player_name'],
            player['position'],
            player
        )
        player_values[player['player_name']] = {
            'position': player['position'],
            'value': value,
            'games': player['games']
        }
    
    # Show top players by value
    sorted_players = sorted(player_values.items(), key=lambda x: x[1]['value'], reverse=True)
    
    print("\nTop 20 Most Valuable Players:")
    print("-" * 60)
    for name, data in sorted_players[:20]:
        print(f"{name:25} {data['position']:3} Value: {data['value']:5.1f}")
    
    return player_values