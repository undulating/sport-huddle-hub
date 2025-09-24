"""
ESPN Complete Player Stats Fetcher - All Players, All Stats (2022-2025)
Gets comprehensive player data, not just leaders
Add to api/adapters/espn_complete_stats.py
"""

import requests
import pandas as pd
import json
import time
from typing import Dict, List, Optional, Set
from datetime import datetime
import logging

logger = logging.getLogger(__name__)

class ESPNCompleteStatsAdapter:
    """
    Fetch complete player statistics from ESPN for all players.
    Covers 2022-2025 seasons with full stat profiles.
    """
    
    def __init__(self):
        self.base_url = "https://site.api.espn.com/apis/site/v2/sports/football/nfl"
        # ESPN Fantasy API has more complete player lists
        self.fantasy_url = "https://fantasy.espn.com/apis/v3/games/ffl/seasons"
        self.headers = {
            'User-Agent': 'Mozilla/5.0 (compatible; NFLStatsBot/1.0)',
            'Accept': 'application/json'
        }
        
    def get_all_players_for_season(self, season: int) -> pd.DataFrame:
        """
        Get ALL players with stats for a given season.
        This uses multiple ESPN endpoints to build complete profiles.
        """
        print(f"Fetching complete {season} player data from ESPN...")
        
        all_players = {}
        
        # 1. Get all teams and rosters
        teams = self._get_all_teams()
        
        for team in teams:
            print(f"  Processing {team['abbreviation']}...")
            roster = self._get_team_roster(team['id'], season)
            
            for player in roster:
                player_id = player['id']
                if player_id not in all_players:
                    all_players[player_id] = player
                
                # Get detailed stats for each player
                stats = self._get_player_season_stats(player_id, season)
                all_players[player_id].update(stats)
                
                # Add game logs for complete picture
                gamelog = self._get_player_gamelog(player_id, season)
                all_players[player_id]['games'] = gamelog
                
                # Be respectful to ESPN's servers
                time.sleep(0.1)
        
        # Convert to DataFrame
        df = pd.DataFrame(list(all_players.values()))
        print(f"✅ Loaded {len(df)} players for {season}")
        
        return df
    
    def get_all_weekly_stats(self, season: int, week: int) -> pd.DataFrame:
        """
        Get complete stats for ALL players for a specific week.
        """
        print(f"Fetching Week {week}, {season} complete stats...")
        
        all_stats = []
        
        # Get all games for the week
        games = self._get_week_games(season, week)
        
        for game in games:
            game_id = game['id']
            print(f"  Processing game {game_id}...")
            
            # Get complete box score with all players
            boxscore = self._get_complete_boxscore(game_id)
            all_stats.extend(boxscore)
            
            time.sleep(0.2)  # Rate limiting
        
        df = pd.DataFrame(all_stats)
        print(f"✅ Loaded {len(df)} player performances for Week {week}, {season}")
        
        return df
    
    def _get_all_teams(self) -> List[Dict]:
        """Get all NFL teams."""
        url = f"{self.base_url}/teams"
        response = requests.get(url, headers=self.headers)
        
        if response.status_code == 200:
            data = response.json()
            return [
                {
                    'id': team['team']['id'],
                    'abbreviation': team['team']['abbreviation'],
                    'name': team['team']['displayName']
                }
                for team in data.get('sports', [{}])[0].get('leagues', [{}])[0].get('teams', [])
            ]
        return []
    
    def _get_team_roster(self, team_id: str, season: int) -> List[Dict]:
        """Get complete roster for a team."""
        url = f"{self.base_url}/teams/{team_id}/roster?season={season}"
        response = requests.get(url, headers=self.headers)
        
        players = []
        if response.status_code == 200:
            data = response.json()
            
            for athlete in data.get('athletes', []):
                players.append({
                    'id': athlete['id'],
                    'name': athlete['fullName'],
                    'display_name': athlete.get('displayName', athlete['fullName']),
                    'jersey': athlete.get('jersey'),
                    'position': athlete.get('position', {}).get('abbreviation'),
                    'height': athlete.get('displayHeight'),
                    'weight': athlete.get('displayWeight'),
                    'age': athlete.get('age'),
                    'experience': athlete.get('experience', {}).get('years'),
                    'headshot': athlete.get('headshot', {}).get('href')
                })
        
        return players
    
    def _get_player_season_stats(self, player_id: str, season: int) -> Dict:
        """Get complete season stats for a player."""
        # ESPN player stats endpoint
        url = f"https://sports.core.api.espn.com/v2/sports/football/leagues/nfl/seasons/{season}/types/2/athletes/{player_id}/statistics"
        
        response = requests.get(url, headers=self.headers)
        
        stats = {}
        if response.status_code == 200:
            data = response.json()
            
            # Parse all available stat categories
            for category in data.get('splits', {}).get('categories', []):
                cat_name = category.get('name', '').lower()
                
                for stat in category.get('stats', []):
                    stat_name = stat.get('name', '').lower().replace(' ', '_')
                    stat_value = stat.get('value', 0)
                    
                    # Map to our standard stat names
                    if 'passing' in cat_name:
                        if 'yards' in stat_name:
                            stats['passing_yards'] = stat_value
                        elif 'touchdowns' in stat_name:
                            stats['passing_tds'] = stat_value
                        elif 'completions' in stat_name:
                            stats['completions'] = stat_value
                        elif 'attempts' in stat_name:
                            stats['passing_attempts'] = stat_value
                        elif 'interceptions' in stat_name:
                            stats['interceptions'] = stat_value
                        elif 'rating' in stat_name:
                            stats['passer_rating'] = stat_value
                            
                    elif 'rushing' in cat_name:
                        if 'yards' in stat_name:
                            stats['rushing_yards'] = stat_value
                        elif 'touchdowns' in stat_name:
                            stats['rushing_tds'] = stat_value
                        elif 'attempts' in stat_name or 'carries' in stat_name:
                            stats['carries'] = stat_value
                        elif 'average' in stat_name:
                            stats['yards_per_carry'] = stat_value
                            
                    elif 'receiving' in cat_name:
                        if 'yards' in stat_name:
                            stats['receiving_yards'] = stat_value
                        elif 'receptions' in stat_name:
                            stats['receptions'] = stat_value
                        elif 'targets' in stat_name:
                            stats['targets'] = stat_value
                        elif 'touchdowns' in stat_name:
                            stats['receiving_tds'] = stat_value
                        elif 'average' in stat_name:
                            stats['yards_per_reception'] = stat_value
        
        return stats
    
    def _get_player_gamelog(self, player_id: str, season: int) -> List[Dict]:
        """Get complete game-by-game log for a player."""
        url = f"https://site.api.espn.com/apis/common/v3/sports/football/nfl/athletes/{player_id}/gamelog?season={season}"
        
        response = requests.get(url, headers=self.headers)
        
        games = []
        if response.status_code == 200:
            data = response.json()
            
            for entry in data.get('entries', []):
                game = {
                    'week': entry.get('week'),
                    'opponent': entry.get('opponent', {}).get('abbreviation'),
                    'home_away': 'home' if entry.get('atHome') else 'away',
                    'result': entry.get('gameResult')
                }
                
                # Parse all stats for this game
                for stat in entry.get('stats', []):
                    stat_name = stat.get('name', '').lower().replace(' ', '_')
                    game[stat_name] = stat.get('value', 0)
                
                games.append(game)
        
        return games
    
    def _get_week_games(self, season: int, week: int) -> List[Dict]:
        """Get all games for a specific week."""
        url = f"{self.base_url}/scoreboard?seasontype=2&week={week}&dates={season}"
        response = requests.get(url, headers=self.headers)
        
        games = []
        if response.status_code == 200:
            data = response.json()
            for event in data.get('events', []):
                games.append({
                    'id': event['id'],
                    'name': event['name'],
                    'date': event['date']
                })
        
        return games
    
    def _get_complete_boxscore(self, game_id: str) -> List[Dict]:
        """Get complete box score with all player stats."""
        url = f"{self.base_url}/summary?event={game_id}"
        response = requests.get(url, headers=self.headers)
        
        players = []
        if response.status_code == 200:
            data = response.json()
            
            # Parse boxscore for all players
            if 'boxscore' in data and 'players' in data['boxscore']:
                for team_data in data['boxscore']['players']:
                    team = team_data['team']['abbreviation']
                    
                    # Process all stat categories
                    for stat_category in team_data.get('statistics', []):
                        category_name = stat_category.get('name', '')
                        
                        for athlete_stats in stat_category.get('athletes', []):
                            athlete = athlete_stats.get('athlete', {})
                            stats = athlete_stats.get('stats', [])
                            
                            player = {
                                'game_id': game_id,
                                'player_id': athlete.get('id'),
                                'player_name': athlete.get('displayName'),
                                'team': team,
                                'position': athlete.get('position', {}).get('abbreviation'),
                                'category': category_name
                            }
                            
                            # Parse stats based on category
                            if category_name == 'passing' and len(stats) >= 3:
                                player['completions_attempts'] = stats[0] if len(stats) > 0 else None
                                player['passing_yards'] = stats[1] if len(stats) > 1 else None
                                player['passing_tds'] = stats[2] if len(stats) > 2 else None
                                
                            elif category_name == 'rushing' and len(stats) >= 3:
                                player['carries'] = stats[0] if len(stats) > 0 else None
                                player['rushing_yards'] = stats[1] if len(stats) > 1 else None
                                player['rushing_tds'] = stats[2] if len(stats) > 2 else None
                                
                            elif category_name == 'receiving' and len(stats) >= 4:
                                player['receptions'] = stats[0] if len(stats) > 0 else None
                                player['receiving_yards'] = stats[1] if len(stats) > 1 else None
                                player['receiving_tds'] = stats[2] if len(stats) > 2 else None
                                player['targets'] = stats[3] if len(stats) > 3 else None
                            
                            players.append(player)
        
        return players
    
    def build_complete_profiles(self, start_season: int = 2022, end_season: int = 2025) -> pd.DataFrame:
        """
        Build complete player profiles across multiple seasons.
        """
        print(f"Building complete player profiles from {start_season} to {end_season}...")
        
        all_seasons_data = []
        
        for season in range(start_season, end_season + 1):
            # Skip future seasons that don't exist yet
            current_year = datetime.now().year
            if season > current_year:
                continue
                
            season_data = self.get_all_players_for_season(season)
            season_data['season'] = season
            all_seasons_data.append(season_data)
            
            # Be respectful between seasons
            time.sleep(1)
        
        # Combine all seasons
        df = pd.concat(all_seasons_data, ignore_index=True)
        
        # Aggregate career stats
        career_stats = df.groupby('id').agg({
            'passing_yards': 'sum',
            'passing_tds': 'sum',
            'rushing_yards': 'sum',
            'rushing_tds': 'sum',
            'receiving_yards': 'sum',
            'receiving_tds': 'sum',
            'receptions': 'sum',
            'name': 'first',
            'position': 'first'
        }).reset_index()
        
        print(f"✅ Built profiles for {len(career_stats)} players across {end_season - start_season + 1} seasons")
        
        return career_stats


# Alternative: Use ESPN Fantasy API for more complete data
class ESPNFantasyStatsAdapter:
    """
    ESPN Fantasy API often has more complete player lists.
    """
    
    def __init__(self):
        self.base_url = "https://fantasy.espn.com/apis/v3/games/ffl"
        
    def get_all_players(self, season: int = 2025) -> pd.DataFrame:
        """
        Get all players from ESPN Fantasy.
        This includes every rostered player.
        """
        # ESPN Fantasy player endpoint - gets ALL players
        url = f"{self.base_url}/seasons/{season}/players?view=players_all"
        
        headers = {
            'x-fantasy-filter': json.dumps({
                "filterActive": {"value": True}
            })
        }
        
        response = requests.get(url, headers=headers)
        
        players = []
        if response.status_code == 200:
            data = response.json()
            
            for player in data.get('players', []):
                player_info = player.get('player', {})
                
                # Get stats from all stat periods
                stats_dict = {}
                for stat in player_info.get('stats', []):
                    if stat.get('seasonId') == season:
                        stats_dict.update(stat.get('stats', {}))
                
                players.append({
                    'id': player_info.get('id'),
                    'name': player_info.get('fullName'),
                    'team': player_info.get('proTeamId'),
                    'position': player_info.get('defaultPositionId'),
                    'stats': stats_dict
                })
        
        return pd.DataFrame(players)


if __name__ == "__main__":
    # Example usage
    adapter = ESPNCompleteStatsAdapter()
    
    # Get complete 2025 Week 1 stats for ALL players
    week1_stats = adapter.get_all_weekly_stats(2025, 1)
    print(f"\n2025 Week 1: {len(week1_stats)} player performances")
    
    # Build complete profiles from 2022-2024
    profiles = adapter.build_complete_profiles(2022, 2024)
    print(f"\nComplete profiles: {len(profiles)} players")
    
    # Show sample profile
    if not profiles.empty:
        top_qb = profiles[profiles['position'] == 'QB'].nlargest(1, 'passing_yards')
        print("\nTop QB by career passing yards (2022-2024):")
        print(top_qb[['name', 'passing_yards', 'passing_tds']])