"""
Working ESPN Stats Adapter - handles current API structure
"""

import requests
import pandas as pd
import json
import time
from typing import Dict, List, Optional
import logging

logger = logging.getLogger(__name__)

class ESPNStatsAdapter:
    """
    Working adapter for ESPN's public API.
    """
    
    def __init__(self):
        self.base_url = "https://site.api.espn.com/apis/site/v2/sports/football/nfl"
        
    def get_all_teams(self) -> List[Dict]:
        """Get all NFL teams."""
        url = f"{self.base_url}/teams"
        response = requests.get(url)
        
        teams = []
        if response.status_code == 200:
            data = response.json()
            for team_entry in data['sports'][0]['leagues'][0]['teams']:
                team = team_entry['team']
                teams.append({
                    'id': team['id'],
                    'abbreviation': team['abbreviation'],
                    'displayName': team['displayName'],
                    'color': team.get('color'),
                    'logo': team.get('logo')
                })
        return teams
    
    def get_team_roster(self, team_id: str) -> List[Dict]:
        """Get complete roster for a team."""
        url = f"{self.base_url}/teams/{team_id}?enable=roster"
        response = requests.get(url)
        
        players = []
        if response.status_code == 200:
            data = response.json()
            if 'team' in data and 'athletes' in data['team']:
                for athlete in data['team']['athletes']:
                    players.append({
                        'id': athlete.get('id'),
                        'fullName': athlete.get('fullName'),
                        'displayName': athlete.get('displayName'),
                        'jersey': athlete.get('jersey'),
                        'position': athlete.get('position', {}).get('abbreviation') if isinstance(athlete.get('position'), dict) else None,
                        'age': athlete.get('age'),
                        'height': athlete.get('displayHeight'),
                        'weight': athlete.get('displayWeight'),
                        'experience': athlete.get('experience', {}).get('years') if isinstance(athlete.get('experience'), dict) else 0
                    })
        return players
    
    def get_current_week_stats(self) -> pd.DataFrame:
        """Get stats from current week games."""
        # Get current scoreboard
        scoreboard_url = f"{self.base_url}/scoreboard"
        response = requests.get(scoreboard_url)
        
        all_stats = []
        if response.status_code == 200:
            data = response.json()
            
            for event in data.get('events', []):
                game_id = event['id']
                
                # Get box score for each game
                summary_url = f"{self.base_url}/summary?event={game_id}"
                summary_response = requests.get(summary_url)
                
                if summary_response.status_code == 200:
                    summary_data = summary_response.json()
                    
                    if 'boxscore' in summary_data and 'players' in summary_data['boxscore']:
                        for team_stats in summary_data['boxscore']['players']:
                            team = team_stats['team']['abbreviation']
                            
                            for stat_category in team_stats.get('statistics', []):
                                for athlete_data in stat_category.get('athletes', []):
                                    athlete = athlete_data.get('athlete', {})
                                    stats = athlete_data.get('stats', [])
                                    
                                    all_stats.append({
                                        'game_id': game_id,
                                        'player_id': athlete.get('id'),
                                        'player_name': athlete.get('displayName'),
                                        'team': team,
                                        'category': stat_category.get('name'),
                                        'stats': stats
                                    })
                
                time.sleep(0.2)  # Rate limiting
        
        return pd.DataFrame(all_stats)
    
    def get_season_leaders(self) -> pd.DataFrame:
        """Get current season statistical leaders."""
        url = f"{self.base_url}/leaders"
        response = requests.get(url)
        
        leaders_data = []
        if response.status_code == 200:
            data = response.json()
            
            for category in data.get('leaders', []):
                cat_name = category.get('displayName')
                
                for leader in category.get('leaders', []):
                    athlete = leader.get('athlete', {})
                    team = athlete.get('team', {})
                    
                    leaders_data.append({
                        'category': cat_name,
                        'player_id': athlete.get('id'),
                        'player_name': athlete.get('displayName'),
                        'position': athlete.get('position', {}).get('abbreviation') if athlete.get('position') else None,
                        'team': team.get('abbreviation') if team else 'FA',
                        'value': leader.get('value'),
                        'displayValue': leader.get('displayValue')
                    })
        
        return pd.DataFrame(leaders_data)

# Usage example
if __name__ == "__main__":
    adapter = ESPNStatsAdapter()
    
    # Get all teams
    teams = adapter.get_all_teams()
    print(f"Found {len(teams)} teams")
    
    # Get roster for first team
    if teams:
        roster = adapter.get_team_roster(teams[0]['id'])
        print(f"Found {len(roster)} players on {teams[0]['displayName']}")
    
    # Get current leaders
    leaders = adapter.get_season_leaders()
    print(f"Found {len(leaders)} leader entries")
