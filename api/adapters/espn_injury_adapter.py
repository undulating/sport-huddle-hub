"""
ESPN Injury Adapter - Free, reliable injury data for NFL teams.
Location: api/adapters/espn_injury_adapter.py
"""
import requests
import logging
from datetime import datetime
from typing import List, Dict, Optional, Any
from api.schemas.provider import InjuryDTO

logger = logging.getLogger(__name__)


class ESPNInjuryAdapter:
    """
    Adapter for ESPN's free injury API.
    This provides up-to-date injury reports for all NFL teams.
    """
    
    def __init__(self):
        self.base_url = "https://site.api.espn.com/apis/site/v2/sports/football/nfl"
        
        # Map ESPN team abbreviations to your system's abbreviations (if different)
        self.team_mapping = {
            'WSH': 'WAS',  # Washington might be different
            'LAR': 'LAR',  # LA Rams
            'LAC': 'LAC',  # LA Chargers
            # Add any other mappings if needed
        }
        
        # ESPN status to your status mapping
        self.status_mapping = {
            'out': 'OUT',
            'doubtful': 'DOUBTFUL',
            'questionable': 'QUESTIONABLE',
            'probable': 'PROBABLE',
            'day-to-day': 'QUESTIONABLE',
            'injured reserve': 'OUT',
            'ir': 'OUT',
            'pup': 'OUT',  # Physically Unable to Perform
        }
    
    def get_all_injuries(self) -> List[InjuryDTO]:
        """
        Get current injury reports for all NFL teams.
        ESPN updates this multiple times daily during the season.
        """
        try:
            url = f"{self.base_url}/injuries"
            response = requests.get(url, timeout=10)
            response.raise_for_status()
            
            data = response.json()
            injuries = []
            
            # The injuries are directly under 'injuries' key, not 'teams'
            for team_data in data.get('injuries', []):
                team_abbr = team_data.get('abbreviation', '')
                if not team_abbr:
                    # Try to get abbreviation from displayName
                    display_name = team_data.get('displayName', '')
                    # Extract abbreviation from team name (e.g., "Arizona Cardinals" -> need lookup)
                    team_abbr = self._get_team_abbr_from_name(display_name)
                
                team_abbr = self.team_mapping.get(team_abbr, team_abbr)
                
                # Each team has an 'injuries' array
                for athlete in team_data.get('injuries', []):
                    injury_dto = self._parse_athlete_injury(athlete, team_abbr)
                    if injury_dto:
                        injuries.append(injury_dto)
            
            logger.info(f"Retrieved {len(injuries)} injury reports from ESPN")
            return injuries
            
        except requests.RequestException as e:
            logger.error(f"Error fetching ESPN injuries: {e}")
            return []
        except Exception as e:
            logger.error(f"Error parsing ESPN injuries: {e}")
            return []

    def _get_team_abbr_from_name(self, team_name: str) -> str:
        """Map team display names to abbreviations."""
        team_name_map = {
            'Arizona Cardinals': 'ARI',
            'Atlanta Falcons': 'ATL',
            'Baltimore Ravens': 'BAL',
            'Buffalo Bills': 'BUF',
            'Carolina Panthers': 'CAR',
            'Chicago Bears': 'CHI',
            'Cincinnati Bengals': 'CIN',
            'Cleveland Browns': 'CLE',
            'Dallas Cowboys': 'DAL',
            'Denver Broncos': 'DEN',
            'Detroit Lions': 'DET',
            'Green Bay Packers': 'GB',
            'Houston Texans': 'HOU',
            'Indianapolis Colts': 'IND',
            'Jacksonville Jaguars': 'JAX',
            'Kansas City Chiefs': 'KC',
            'Las Vegas Raiders': 'LV',
            'Los Angeles Chargers': 'LAC',
            'Los Angeles Rams': 'LAR',
            'Miami Dolphins': 'MIA',
            'Minnesota Vikings': 'MIN',
            'New England Patriots': 'NE',
            'New Orleans Saints': 'NO',
            'New York Giants': 'NYG',
            'New York Jets': 'NYJ',
            'Philadelphia Eagles': 'PHI',
            'Pittsburgh Steelers': 'PIT',
            'San Francisco 49ers': 'SF',
            'Seattle Seahawks': 'SEA',
            'Tampa Bay Buccaneers': 'TB',
            'Tennessee Titans': 'TEN',
            'Washington Commanders': 'WAS'
        }
        return team_name_map.get(team_name, team_name[:3].upper())

    def _parse_athlete_injury(self, athlete_data: Dict, team_abbr: str) -> Optional[InjuryDTO]:
        """Parse individual athlete injury data from ESPN format."""
        try:
            # The structure is different - adjust parsing
            player_name = athlete_data.get('athlete', {}).get('displayName', '')
            if not player_name:
                player_name = athlete_data.get('fullName', 'Unknown')
            
            # Get position
            position = athlete_data.get('athlete', {}).get('position', {}).get('abbreviation', '')
            if not position:
                position = 'Unknown'
            
            # Get jersey number
            jersey = athlete_data.get('athlete', {}).get('jersey')
            
            # Get injury status
            status = athlete_data.get('status', 'questionable').lower()
            status = self.status_mapping.get(status, 'QUESTIONABLE')
            
            # Get injury description from longComment
            injury_description = athlete_data.get('longComment', '')
            if not injury_description:
                injury_description = athlete_data.get('shortComment', 'Unknown')
            
            # Extract injury type from description (first few words usually contain it)
            if injury_description:
                # Look for common injury keywords
                injury_keywords = ['concussion', 'hamstring', 'knee', 'ankle', 'shoulder', 
                                'back', 'groin', 'quad', 'calf', 'foot', 'hip', 'chest',
                                'ribs', 'wrist', 'elbow', 'neck', 'abdomen']
                injury_type = 'Unknown'
                for keyword in injury_keywords:
                    if keyword.lower() in injury_description.lower():
                        injury_type = keyword.capitalize()
                        break
            else:
                injury_type = 'Unknown'
            
            return InjuryDTO(
                team_external_id=team_abbr,
                player_name=player_name,
                player_position=position,
                player_number=int(jersey) if jersey else None,
                injury_status=status,
                injury_type=injury_type,
                season=datetime.now().year,
                week=self._get_current_nfl_week(),
                report_date=datetime.now()
            )
            
        except Exception as e:
            logger.debug(f"Error parsing athlete injury: {e}")
            return None
    
    def _get_current_nfl_week(self) -> int:
        """
        Determine current NFL week based on date.
        This is a simple calculation - you might want to make it more sophisticated.
        """
        # NFL season typically starts first week of September
        now = datetime.now()
        
        # Simple logic - you can enhance this
        if now.month < 9:
            return 1  # Pre-season or off-season
        elif now.month == 9:
            return min((now.day // 7) + 1, 4)
        elif now.month == 10:
            return min(4 + ((now.day // 7) + 1), 8)
        elif now.month == 11:
            return min(8 + ((now.day // 7) + 1), 13)
        elif now.month == 12:
            return min(13 + ((now.day // 7) + 1), 17)
        else:
            return 18  # Playoffs
    
    def get_key_injuries(self, min_games_missed: int = 0) -> Dict[str, List[Dict]]:
        """
        Get only key injuries (QBs, star players) organized by team.
        
        Returns:
            Dict with team abbreviations as keys and list of key injuries as values
        """
        all_injuries = self.get_all_injuries()
        
        # Define key positions
        key_positions = ['QB', 'RB', 'WR', 'TE', 'EDGE', 'CB']
        
        # Filter for key injuries
        key_injuries = {}
        
        for injury in all_injuries:
            # Only include OUT or DOUBTFUL for key positions
            if (injury.player_position in key_positions and 
                injury.injury_status in ['OUT', 'DOUBTFUL']):
                
                team = injury.team_external_id
                if team not in key_injuries:
                    key_injuries[team] = []
                
                key_injuries[team].append({
                    'player': injury.player_name,
                    'position': injury.player_position,
                    'status': injury.injury_status,
                    'injury': injury.injury_type
                })
        
        return key_injuries


# Integration with your existing system
def sync_espn_injuries():
    """
    Sync ESPN injuries to your database.
    Run this before generating predictions.
    """
    from api.storage.db import get_db_context
    from api.storage.models import Team, Injury
    
    adapter = ESPNInjuryAdapter()
    injuries = adapter.get_all_injuries()
    
    with get_db_context() as db:
        # Clear old injuries (optional - you might want to keep history)
        current_week = adapter._get_current_nfl_week()
        current_season = datetime.now().year
        
        # Delete old injuries for current week
        db.query(Injury).filter(
            Injury.season == current_season,
            Injury.week == current_week
        ).delete()
        
        # Add new injuries
        for injury_dto in injuries:
            # Find team
            team = db.query(Team).filter(
                Team.abbreviation == injury_dto.team_external_id
            ).first()
            
            if team:
                injury = Injury(
                    team_id=team.id,
                    player_name=injury_dto.player_name,
                    player_position=injury_dto.player_position,
                    player_number=injury_dto.player_number,
                    injury_status=injury_dto.injury_status,
                    injury_type=injury_dto.injury_type,
                    season=injury_dto.season,
                    week=injury_dto.week,
                    report_date=injury_dto.report_date,
                    provider='espn'
                )
                db.add(injury)
        
        db.commit()
        logger.info(f"Synced {len(injuries)} injuries from ESPN")
    
    return len(injuries)


# Script to test the adapter
if __name__ == "__main__":
    # Test the adapter
    adapter = ESPNInjuryAdapter()
    
    print("Fetching all NFL injuries from ESPN...")
    injuries = adapter.get_all_injuries()
    
    print(f"\nFound {len(injuries)} total injuries")
    
    # Show key injuries
    key_injuries = adapter.get_key_injuries()
    
    print("\n=== KEY INJURIES BY TEAM ===")
    for team, team_injuries in sorted(key_injuries.items()):
        if team_injuries:
            print(f"\n{team}:")
            for inj in team_injuries:
                print(f"  - {inj['player']} ({inj['position']}): {inj['status']} - {inj['injury']}")
    
    # Test team-specific
    print("\n=== BILLS INJURIES ===")
    bills_injuries = adapter.get_team_injuries('BUF')
    for inj in bills_injuries:
        print(f"  - {inj.player_name} ({inj.player_position}): {inj.injury_status}")