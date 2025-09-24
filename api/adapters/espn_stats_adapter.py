"""
ESPN Stats Scraper for 2025 NFL Player Data
Free alternative to get current season stats
Add this to api/adapters/espn_stats_adapter.py
"""

import requests
import pandas as pd
import json
from typing import Dict, List, Optional
from datetime import datetime
import logging

logger = logging.getLogger(__name__)

class ESPNStatsAdapter:
    """
    Scrape current NFL player stats from ESPN's public API.
    ESPN provides free access to current season data.
    """
    
    def __init__(self):
        self.base_url = "https://site.api.espn.com/apis/site/v2/sports/football/nfl"
        self.athletes_url = "https://sports.core.api.espn.com/v2/sports/football/leagues/nfl/seasons/2025/types/2/athletes"
        
    def get_current_week_stats(self) -> pd.DataFrame:
        """
        Get current week player stats from ESPN.
        """
        try:
            # ESPN's scoreboard API gives us current week games
            scoreboard_url = f"{self.base_url}/scoreboard"
            response = requests.get(scoreboard_url)
            data = response.json()
            
            all_players = []
            
            for event in data.get('events', []):
                game_id = event['id']
                
                # Get box score for each game
                boxscore_url = f"{self.base_url}/summary?event={game_id}"
                box_response = requests.get(boxscore_url)
                
                if box_response.status_code == 200:
                    box_data = box_response.json()
                    
                    # Extract player stats from boxscore
                    if 'boxscore' in box_data:
                        players = self._parse_boxscore_players(box_data['boxscore'])
                        all_players.extend(players)
            
            return pd.DataFrame(all_players)
            
        except Exception as e:
            logger.error(f"Error fetching ESPN stats: {e}")
            return pd.DataFrame()
    
    def get_season_leaders(self, stat_type: str = "passing") -> pd.DataFrame:
        """
        Get season statistical leaders.
        stat_type: 'passing', 'rushing', 'receiving'
        """
        try:
            # ESPN leaders endpoint
            leaders_url = f"{self.base_url}/leaders?season=2025&seasontype=2"
            
            response = requests.get(leaders_url)
            data = response.json()
            
            leaders = []
            for category in data.get('leaders', []):
                if stat_type in category['name'].lower():
                    for leader in category.get('leaders', []):
                        athlete = leader['athlete']
                        leaders.append({
                            'player_id': athlete['id'],
                            'player_name': athlete['displayName'],
                            'team': athlete.get('team', {}).get('abbreviation', ''),
                            'position': athlete.get('position', {}).get('abbreviation', ''),
                            'value': leader['value'],
                            'stat_name': category['displayName']
                        })
            
            return pd.DataFrame(leaders)
            
        except Exception as e:
            logger.error(f"Error fetching ESPN leaders: {e}")
            return pd.DataFrame()
    
    def get_player_gamelog(self, player_id: str, season: int = 2025) -> pd.DataFrame:
        """
        Get specific player's game log for the season.
        """
        try:
            gamelog_url = f"https://site.api.espn.com/apis/common/v3/sports/football/nfl/athletes/{player_id}/gamelog?season={season}"
            
            response = requests.get(gamelog_url)
            data = response.json()
            
            games = []
            for event in data.get('events', {}).get('events', []):
                stats = event.get('stats', {})
                games.append({
                    'week': event.get('week'),
                    'opponent': event.get('opponent', {}).get('abbreviation'),
                    'passing_yards': stats.get('passingYards'),
                    'passing_tds': stats.get('passingTouchdowns'),
                    'rushing_yards': stats.get('rushingYards'),
                    'rushing_tds': stats.get('rushingTouchdowns'),
                    'receiving_yards': stats.get('receivingYards'),
                    'receptions': stats.get('receptions'),
                    'targets': stats.get('targets')
                })
            
            return pd.DataFrame(games)
            
        except Exception as e:
            logger.error(f"Error fetching player gamelog: {e}")
            return pd.DataFrame()
    
    def _parse_boxscore_players(self, boxscore: Dict) -> List[Dict]:
        """
        Parse player stats from ESPN boxscore data.
        """
        players = []
        
        # Parse each team's players
        for team_data in boxscore.get('players', []):
            team = team_data.get('team', {}).get('abbreviation', '')
            
            # Passing stats
            for player in team_data.get('statistics', [{}])[0].get('athletes', []):
                if 'passingYards' in player.get('stats', {}):
                    players.append(self._create_player_record(player, team, 'QB'))
            
            # Rushing stats
            if len(team_data.get('statistics', [])) > 1:
                for player in team_data['statistics'][1].get('athletes', []):
                    if 'rushingYards' in player.get('stats', {}):
                        players.append(self._create_player_record(player, team, 'RB'))
            
            # Receiving stats
            if len(team_data.get('statistics', [])) > 2:
                for player in team_data['statistics'][2].get('athletes', []):
                    if 'receivingYards' in player.get('stats', {}):
                        players.append(self._create_player_record(player, team, 'WR'))
        
        return players
    
    def _create_player_record(self, player_data: Dict, team: str, position: str) -> Dict:
        """
        Create standardized player record.
        """
        stats = player_data.get('stats', {})
        athlete = player_data.get('athlete', {})
        
        return {
            'player_id': athlete.get('id'),
            'player_name': athlete.get('displayName'),
            'team': team,
            'position': position,
            'passing_yards': stats.get('passingYards'),
            'passing_tds': stats.get('passingTouchdowns'),
            'completions': stats.get('completions'),
            'attempts': stats.get('passingAttempts'),
            'rushing_yards': stats.get('rushingYards'),
            'rushing_tds': stats.get('rushingTouchdowns'),
            'carries': stats.get('rushingAttempts'),
            'receiving_yards': stats.get('receivingYards'),
            'receptions': stats.get('receptions'),
            'targets': stats.get('receivingTargets'),
            'receiving_tds': stats.get('receivingTouchdowns')
        }


class ProFootballReferenceScaper:
    """
    Alternative: Scrape from Pro Football Reference
    Note: Be respectful of their servers - add delays between requests
    """
    
    def __init__(self):
        self.base_url = "https://www.pro-football-reference.com"
        self.headers = {
            'User-Agent': 'Mozilla/5.0 (compatible; NFLStatsBot/1.0)'
        }
    
    def get_week_stats(self, year: int = 2025, week: int = 1) -> pd.DataFrame:
        """
        Scrape weekly stats from PFR.
        Note: This is a simplified example - PFR uses JavaScript rendering
        so you might need Selenium for full functionality.
        """
        import time
        
        try:
            # Construct URL for weekly stats
            url = f"{self.base_url}/years/{year}/week_{week}.htm"
            
            # Be respectful - add delay
            time.sleep(1)
            
            response = requests.get(url, headers=self.headers)
            
            if response.status_code == 200:
                # Parse with pandas (PFR has HTML tables)
                tables = pd.read_html(response.text)
                
                # Process tables to extract player stats
                # This would need more parsing logic
                return tables[0] if tables else pd.DataFrame()
            
            return pd.DataFrame()
            
        except Exception as e:
            logger.error(f"Error scraping PFR: {e}")
            return pd.DataFrame()


class SportsDataIOFree:
    """
    Sports Data IO offers some free endpoints.
    Limited to 1000 calls per month on free tier.
    """
    
    def __init__(self):
        # They offer a free trial key
        self.api_key = "YOUR_FREE_TRIAL_KEY"  # Sign up at sportsdata.io
        self.base_url = "https://api.sportsdata.io/v3/nfl/stats/json"
    
    def get_current_week(self) -> Dict:
        """
        Get current week info.
        """
        url = f"{self.base_url}/CurrentWeek"
        headers = {"Ocp-Apim-Subscription-Key": self.api_key}
        
        response = requests.get(url, headers=headers)
        return response.json() if response.status_code == 200 else {}
    
    def get_player_stats_by_week(self, season: int, week: int) -> List[Dict]:
        """
        Get player stats for a specific week.
        """
        url = f"{self.base_url}/PlayerGameStatsByWeek/{season}/{week}"
        headers = {"Ocp-Apim-Subscription-Key": self.api_key}
        
        response = requests.get(url, headers=headers)
        return response.json() if response.status_code == 200 else []


# Integration function to combine sources
def get_latest_player_stats() -> pd.DataFrame:
    """
    Get 2025 player stats from available free sources.
    """
    print("Fetching 2025 player stats from free sources...")
    
    # Try ESPN first (most reliable free source)
    espn = ESPNStatsAdapter()
    
    # Get current week stats
    current_stats = espn.get_current_week_stats()
    if not current_stats.empty:
        print(f"✅ Loaded {len(current_stats)} players from ESPN")
        return current_stats
    
    # Fallback to other sources if needed
    print("⚠️ ESPN data not available, trying alternatives...")
    
    # You could add PFR or other scrapers here
    
    return pd.DataFrame()


if __name__ == "__main__":
    # Test the ESPN adapter
    adapter = ESPNStatsAdapter()
    
    # Get current stats
    stats = adapter.get_current_week_stats()
    print(f"Found {len(stats)} player records")
    
    # Get season leaders
    qb_leaders = adapter.get_season_leaders("passing")
    print(f"\nTop QBs:")
    print(qb_leaders.head())
    
    rb_leaders = adapter.get_season_leaders("rushing")
    print(f"\nTop RBs:")
    print(rb_leaders.head())