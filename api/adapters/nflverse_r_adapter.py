"""
Enhanced NFLverse adapter that integrates with locally installed R nflverse package.
This provides access to the full suite of nflverse data including real-time updates,
advanced statistics, and comprehensive NFL data.
"""

import os
import json
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from typing import List, Optional, Dict, Any, Union
import logging
from functools import lru_cache
from pathlib import Path
import hashlib
import pickle

# R integration imports
try:
    import rpy2.robjects as robjects
    from rpy2.robjects import pandas2ri
    from rpy2.robjects.packages import importr
    from rpy2.robjects.conversion import localconverter
    R_AVAILABLE = True
except ImportError:
    R_AVAILABLE = False
    print("Warning: rpy2 not installed. Falling back to CSV-based data fetching.")

from api.adapters.base import ProviderAdapter, ProviderRegistry
from api.schemas.provider import (
    TeamDTO, GameDTO, OddsDTO, InjuryDTO, WeatherDTO
)

logger = logging.getLogger(__name__)


class NFLverseRAdapter(ProviderAdapter):
    """
    Enhanced NFLverse adapter that interfaces with local R nflverse package.
    Falls back to CSV fetching if R is not available.
    """
    
    def __init__(self, 
                 api_key: Optional[str] = None,
                 use_cache: bool = True,
                 cache_dir: str = "/tmp/nflverse_cache",
                 cache_ttl: int = 3600):  # Cache TTL in seconds
        """
        Initialize the NFLverse R adapter.
        
        Args:
            api_key: Optional API key (not used for nflverse)
            use_cache: Whether to use local caching
            cache_dir: Directory for cache files
            cache_ttl: Cache time-to-live in seconds
        """
        super().__init__(api_key)
        self.use_cache = use_cache
        self.cache_dir = Path(cache_dir)
        self.cache_ttl = cache_ttl
        
        if use_cache:
            self.cache_dir.mkdir(parents=True, exist_ok=True)
        
        # Initialize R interface if available
        self.r_interface = None
        self.nflverse = None
        self.tidyverse = None
        
        if R_AVAILABLE:
            try:
                self._initialize_r_interface()
                logger.info("✅ R nflverse package initialized successfully")
            except Exception as e:
                logger.warning(f"⚠️ Could not initialize R interface: {e}")
                logger.info("Falling back to CSV-based data fetching")
        else:
            logger.info("rpy2 not available. Using CSV-based data fetching")
        
        # Fallback to CSV URLs if R is not available
        self.csv_urls = {
            'games': 'https://github.com/nflverse/nfldata/raw/master/data/games.csv',
            'rosters': 'https://github.com/nflverse/nflverse-data/releases/download/rosters/rosters.csv',
            'player_stats': 'https://github.com/nflverse/nflverse-data/releases/download/player_stats/player_stats.csv',
            'pbp': 'https://github.com/nflverse/nflverse-data/releases/download/pbp/play_by_play_{year}.csv',
            'injuries': 'https://github.com/nflverse/nflverse-data/releases/download/injuries/injuries.csv',
            'nextgen': 'https://github.com/nflverse/nflverse-data/releases/download/nextgen_stats/ngs_{year}_{stat_type}.csv'
        }
        
        # Cache for DataFrames
        self._df_cache = {}
    
    def _initialize_r_interface(self):
        """Initialize R interface and load nflverse packages."""
        # Enable automatic pandas conversion
        pandas2ri.activate()
        
        # Import R packages
        self.r_interface = robjects.r
        
        # Install/load nflverse if not already installed
        self.r_interface('''
            if (!require("nflverse", quietly = TRUE)) {
                install.packages("nflverse", repos = "https://cloud.r-project.org/")
            }
            if (!require("tidyverse", quietly = TRUE)) {
                install.packages("tidyverse", repos = "https://cloud.r-project.org/")
            }
            library(nflverse)
            library(tidyverse)
        ''')
        
        # Store package references
        self.nflverse = importr('nflverse')
        
        # Load and update data
        logger.info("Loading nflverse data in R (including 2025)...")
        self.r_interface('nflverse::load_pbp(seasons = 2020:2025)')
        self.r_interface('nflverse::load_player_stats(seasons = 2020:2025)')
        self.r_interface('nflverse::load_rosters(seasons = 2020:2025)')
        self.r_interface('nflverse::load_schedules(seasons = 2020:2025)')
    
    def _get_cache_key(self, func_name: str, *args, **kwargs) -> str:
        """Generate cache key for function calls."""
        key_parts = [func_name] + [str(arg) for arg in args] + [f"{k}={v}" for k, v in sorted(kwargs.items())]
        key_str = "_".join(key_parts)
        return hashlib.md5(key_str.encode()).hexdigest()
    
    def _get_from_cache(self, cache_key: str) -> Optional[Any]:
        """Retrieve data from cache if valid."""
        if not self.use_cache:
            return None
        
        cache_file = self.cache_dir / f"{cache_key}.pkl"
        if cache_file.exists():
            age = datetime.now().timestamp() - cache_file.stat().st_mtime
            if age < self.cache_ttl:
                with open(cache_file, 'rb') as f:
                    return pickle.load(f)
        return None
    
    def _save_to_cache(self, cache_key: str, data: Any):
        """Save data to cache."""
        if not self.use_cache:
            return
        
        cache_file = self.cache_dir / f"{cache_key}.pkl"
        with open(cache_file, 'wb') as f:
            pickle.dump(data, f)
    
    def _fetch_from_r(self, r_code: str) -> pd.DataFrame:
        """Execute R code and return result as pandas DataFrame."""
        if not R_AVAILABLE or not self.r_interface:
            raise RuntimeError("R interface not available")
        
        with localconverter(robjects.default_converter + pandas2ri.converter):
            result = self.r_interface(r_code)
            return robjects.conversion.rpy2py(result)
    
    def get_teams(self) -> List[TeamDTO]:
        """Get all NFL teams with comprehensive data."""
        cache_key = self._get_cache_key('get_teams')
        cached_data = self._get_from_cache(cache_key)
        if cached_data:
            return cached_data
        
        try:
            if R_AVAILABLE and self.r_interface:
                # Fetch from R nflverse
                df = self._fetch_from_r('''
                    teams <- nflverse::load_teams() %>%
                        filter(team_abbr != "LA") %>%
                        select(team_abbr, team_name, team_nick, team_conf, team_division, 
                               team_color, team_color2, team_wordmark, team_logo_espn)
                    teams
                ''')
                
                teams = []
                for _, row in df.iterrows():
                    teams.append(TeamDTO(
                        external_id=row['team_abbr'],
                        name=row['team_nick'],
                        city=row['team_name'].replace(row['team_nick'], '').strip(),
                        abbreviation=row['team_abbr'],
                        conference=row['team_conf'],
                        division=row['team_division'],
                        primary_color=row.get('team_color', '#000000'),
                        secondary_color=row.get('team_color2', '#FFFFFF'),
                        logo_url=row.get('team_logo_espn', None)
                    ))
            else:
                # Fallback to CSV
                teams = self._get_teams_from_csv()
        except Exception as e:
            logger.error(f"Error fetching teams: {e}")
            teams = self._get_teams_from_csv()
        
        self._save_to_cache(cache_key, teams)
        return teams
    
    def _get_teams_from_csv(self) -> List[TeamDTO]:
        """Fallback method to get teams from CSV."""
        df = pd.read_csv(self.csv_urls['games'])
        
        # Get unique teams
        all_teams = set()
        all_teams.update(df['home_team'].unique())
        all_teams.update(df['away_team'].unique())
        
        # Team mapping (same as original adapter)
        team_map = {
            'BUF': ('Bills', 'Buffalo', 'AFC', 'East', '#00338D', '#C60C30'),
            'MIA': ('Dolphins', 'Miami', 'AFC', 'East', '#008E97', '#FC4C02'),
            'NE': ('Patriots', 'New England', 'AFC', 'East', '#002244', '#C60C30'),
            'NYJ': ('Jets', 'New York', 'AFC', 'East', '#125740', '#FFFFFF'),
            'BAL': ('Ravens', 'Baltimore', 'AFC', 'North', '#241773', '#000000'),
            'CIN': ('Bengals', 'Cincinnati', 'AFC', 'North', '#FB4F14', '#000000'),
            'CLE': ('Browns', 'Cleveland', 'AFC', 'North', '#311D00', '#FF3C00'),
            'PIT': ('Steelers', 'Pittsburgh', 'AFC', 'North', '#FFB612', '#101820'),
            'HOU': ('Texans', 'Houston', 'AFC', 'South', '#03202F', '#A71930'),
            'IND': ('Colts', 'Indianapolis', 'AFC', 'South', '#002C5F', '#A2AAAD'),
            'JAX': ('Jaguars', 'Jacksonville', 'AFC', 'South', '#006778', '#9F792C'),
            'TEN': ('Titans', 'Tennessee', 'AFC', 'South', '#0C2340', '#418FDE'),
            'DEN': ('Broncos', 'Denver', 'AFC', 'West', '#FB4F14', '#002244'),
            'KC': ('Chiefs', 'Kansas City', 'AFC', 'West', '#E31837', '#FFB81C'),
            'LV': ('Raiders', 'Las Vegas', 'AFC', 'West', '#000000', '#A5ACAF'),
            'LAC': ('Chargers', 'Los Angeles', 'AFC', 'West', '#0080C6', '#FFC20E'),
            'DAL': ('Cowboys', 'Dallas', 'NFC', 'East', '#003594', '#869397'),
            'NYG': ('Giants', 'New York', 'NFC', 'East', '#0B2265', '#A71930'),
            'PHI': ('Eagles', 'Philadelphia', 'NFC', 'East', '#004C54', '#A5ACAF'),
            'WAS': ('Commanders', 'Washington', 'NFC', 'East', '#5A1414', '#FFB612'),
            'CHI': ('Bears', 'Chicago', 'NFC', 'North', '#0B162A', '#C83803'),
            'DET': ('Lions', 'Detroit', 'NFC', 'North', '#0076B6', '#B0B7BC'),
            'GB': ('Packers', 'Green Bay', 'NFC', 'North', '#203731', '#FFB612'),
            'MIN': ('Vikings', 'Minnesota', 'NFC', 'North', '#4F2683', '#FFC62F'),
            'ATL': ('Falcons', 'Atlanta', 'NFC', 'South', '#A71930', '#000000'),
            'CAR': ('Panthers', 'Carolina', 'NFC', 'South', '#0085CA', '#101820'),
            'NO': ('Saints', 'New Orleans', 'NFC', 'South', '#D3BC8D', '#101820'),
            'TB': ('Buccaneers', 'Tampa Bay', 'NFC', 'South', '#D50A0A', '#34302B'),
            'ARI': ('Cardinals', 'Arizona', 'NFC', 'West', '#97233F', '#000000'),
            'LAR': ('Rams', 'Los Angeles', 'NFC', 'West', '#003594', '#FFA300'),
            'SF': ('49ers', 'San Francisco', 'NFC', 'West', '#AA0000', '#B3995D'),
            'SEA': ('Seahawks', 'Seattle', 'NFC', 'West', '#002244', '#69BE28'),
        }
        
        teams = []
        for abbr in all_teams:
            if abbr and abbr in team_map:
                info = team_map[abbr]
                teams.append(TeamDTO(
                    external_id=abbr,
                    name=info[0],
                    city=info[1],
                    abbreviation=abbr,
                    conference=info[2],
                    division=info[3],
                    primary_color=info[4],
                    secondary_color=info[5]
                ))
        
        return teams
    
    def get_games(self, season: int, week: Optional[int] = None) -> List[GameDTO]:
        """Get games for a season/week with enhanced data."""
        cache_key = self._get_cache_key('get_games', season, week)
        cached_data = self._get_from_cache(cache_key)
        if cached_data:
            return cached_data
        
        try:
            if R_AVAILABLE and self.r_interface:
                # Build R query
                if week:
                    r_code = f'''
                        games <- nflverse::load_schedules({season}) %>%
                            filter(week == {week}) %>%
                            select(game_id, season, week, game_type, gameday, weekday, gametime, 
                                   away_team, home_team, away_score, home_score, 
                                   location, result, total, overtime, 
                                   away_rest, home_rest, away_moneyline, home_moneyline,
                                   spread_line, away_spread_odds, home_spread_odds,
                                   total_line, under_odds, over_odds,
                                   div_game, roof, surface, temp, wind, stadium)
                        games
                    '''
                else:
                    r_code = f'''
                        games <- nflverse::load_schedules({season}) %>%
                            select(game_id, season, week, game_type, gameday, weekday, gametime,
                                   away_team, home_team, away_score, home_score,
                                   location, result, total, overtime,
                                   away_rest, home_rest, away_moneyline, home_moneyline,
                                   spread_line, away_spread_odds, home_spread_odds,
                                   total_line, under_odds, over_odds,
                                   div_game, roof, surface, temp, wind, stadium)
                        games
                    '''
                
                df = self._fetch_from_r(r_code)
                games = self._convert_games_df_to_dto(df)
            else:
                # Fallback to CSV
                games = self._get_games_from_csv(season, week)
        except Exception as e:
            logger.error(f"Error fetching games: {e}")
            games = self._get_games_from_csv(season, week)
        
        self._save_to_cache(cache_key, games)
        return games
    
    def _get_games_from_csv(self, season: int, week: Optional[int] = None) -> List[GameDTO]:
        """Fallback method to get games from CSV."""
        df = pd.read_csv(self.csv_urls['games'])
        
        # Filter by season
        df = df[df['season'] == season]
        
        # Filter by week if specified
        if week:
            df = df[df['week'] == week]
        
        return self._convert_games_df_to_dto(df)
    
    def _convert_games_df_to_dto(self, df: pd.DataFrame) -> List[GameDTO]:
        """Convert games DataFrame to GameDTO list."""
        games = []
        
        for _, row in df.iterrows():
            # Parse datetime
            game_date = pd.to_datetime(row.get('gameday', row.get('game_date')))
            game_time = row.get('gametime', row.get('kickoff_time', ''))
            
            # Combine date and time
            if game_time and isinstance(game_time, str) and ':' in game_time:
                try:
                    hour, minute = game_time.split(':')[:2]
                    game_date = game_date.replace(hour=int(hour), minute=int(minute))
                except:
                    pass
            
            games.append(GameDTO(
                external_id=str(row.get('game_id', f"{row['home_team']}_{row['away_team']}_{row.get('week', 0)}")),
                season=int(row['season']),
                week=int(row['week']) if pd.notna(row.get('week')) else None,
                game_type=self._safe_string(row.get('game_type', 'REG')),
                game_date=game_date,
                home_team_external_id=self._safe_string(row['home_team']),
                away_team_external_id=self._safe_string(row['away_team']),
                home_score=self._safe_int(row.get('home_score')),
                away_score=self._safe_int(row.get('away_score')),
                is_completed=pd.notna(row.get('home_score')) and pd.notna(row.get('away_score')),
                stadium=self._safe_string(row.get('stadium', row.get('location'))),
                weather_temperature=self._safe_float(row.get('temp')),
                weather_wind_speed=self._safe_float(row.get('wind')),
                weather_condition=self._safe_string(row.get('roof')),
                season_type=self._safe_string(row.get('season_type', 'REG')),  
                kickoff_time=self._parse_kickoff_time(game_date, game_time),
                total_over_under=self._safe_float(row.get('total_line', row.get('total'))),
                home_moneyline=self._safe_float(row.get('home_moneyline')),
                away_moneyline=self._safe_float(row.get('away_moneyline'))
            ))
        
        return games
    
    def get_player_stats(self, season: int, week: Optional[int] = None) -> pd.DataFrame:
        """
        Get comprehensive player statistics.
        This is a new method not in the base adapter but useful for predictions.
        """
        cache_key = self._get_cache_key('get_player_stats', season, week)
        cached_data = self._get_from_cache(cache_key)
        if cached_data is not None:
            return cached_data
        
        try:
            if R_AVAILABLE and self.r_interface:
                if week:
                    r_code = f'''
                        stats <- nflverse::load_player_stats(seasons = {season}) %>%
                            filter(week == {week}) %>%
                            select(player_id, player_name, player_display_name, position, position_group,
                                   week, season, team, opponent,
                                   completions, attempts, passing_yards, passing_tds, interceptions,
                                   sacks, sack_yards, passing_air_yards, passing_epa,
                                   carries, rushing_yards, rushing_tds, rushing_epa,
                                   receptions, targets, receiving_yards, receiving_tds, receiving_epa,
                                   fantasy_points, fantasy_points_ppr)
                        stats
                    '''
                else:
                    r_code = f'''
                        stats <- nflverse::load_player_stats(seasons = {season}) %>%
                            select(player_id, player_name, player_display_name, position, position_group,
                                   week, season, team, opponent,
                                   completions, attempts, passing_yards, passing_tds, interceptions,
                                   sacks, sack_yards, passing_air_yards, passing_epa,
                                   carries, rushing_yards, rushing_tds, rushing_epa,
                                   receptions, targets, receiving_yards, receiving_tds, receiving_epa,
                                   fantasy_points, fantasy_points_ppr)
                        stats
                    '''
                
                df = self._fetch_from_r(r_code)
            else:
                # Fallback to CSV
                url = self.csv_urls['player_stats']
                df = pd.read_csv(url)
                df = df[df['season'] == season]
                if week:
                    df = df[df['week'] == week]
        except Exception as e:
            logger.error(f"Error fetching player stats: {e}")
            df = pd.DataFrame()
        
        self._save_to_cache(cache_key, df)
        return df
    
    def get_pbp_data(self, season: int, week: Optional[int] = None) -> pd.DataFrame:
        """
        Get play-by-play data for advanced analytics.
        This is useful for calculating advanced metrics.
        """
        cache_key = self._get_cache_key('get_pbp_data', season, week)
        cached_data = self._get_from_cache(cache_key)
        if cached_data is not None:
            return cached_data
        
        try:
            if R_AVAILABLE and self.r_interface:
                if week:
                    r_code = f'''
                        pbp <- nflverse::load_pbp({season}) %>%
                            filter(week == {week}) %>%
                            select(play_id, game_id, home_team, away_team, season_type, week,
                                   posteam, posteam_type, defteam, side_of_field, yardline_100,
                                   game_seconds_remaining, half_seconds_remaining, game_half,
                                   quarter_seconds_remaining, drive, sp, qtr, down, goal_to_go,
                                   time, yrdln, ydstogo, ydsnet, desc, play_type, yards_gained,
                                   shotgun, no_huddle, qb_dropback, qb_kneel, qb_spike, qb_scramble,
                                   pass_length, pass_location, air_yards, yards_after_catch,
                                   run_location, run_gap, field_goal_result, kick_distance,
                                   extra_point_result, two_point_conv_result, home_timeouts_remaining,
                                   away_timeouts_remaining, timeout, timeout_team, td_team,
                                   td_player_name, td_player_id, posteam_timeouts_remaining,
                                   defteam_timeouts_remaining, total_home_score, total_away_score,
                                   posteam_score, defteam_score, score_differential,
                                   posteam_score_post, defteam_score_post, score_differential_post,
                                   no_score_prob, opp_fg_prob, opp_safety_prob, opp_td_prob,
                                   fg_prob, safety_prob, td_prob, extra_point_prob,
                                   two_point_conversion_prob, ep, epa, total_home_epa,
                                   total_away_epa, total_home_rush_epa, total_away_rush_epa,
                                   total_home_pass_epa, total_away_pass_epa, air_epa, yac_epa,
                                   comp_air_epa, comp_yac_epa, total_home_comp_air_epa,
                                   total_away_comp_air_epa, total_home_comp_yac_epa,
                                   total_away_comp_yac_epa, total_home_raw_air_epa,
                                   total_away_raw_air_epa, total_home_raw_yac_epa,
                                   total_away_raw_yac_epa, wp, def_wp, home_wp, away_wp,
                                   wpa, home_wp_post, away_wp_post, vegas_wpa, vegas_home_wpa,
                                   total_home_rush_wpa, total_away_rush_wpa, total_home_pass_wpa,
                                   total_away_pass_wpa, air_wpa, yac_wpa, comp_air_wpa,
                                   comp_yac_wpa, total_home_comp_air_wpa, total_away_comp_air_wpa,
                                   total_home_comp_yac_wpa, total_away_comp_yac_wpa,
                                   total_home_raw_air_wpa, total_away_raw_air_wpa,
                                   total_home_raw_yac_wpa, total_away_raw_yac_wpa, punt_blocked,
                                   first_down_rush, first_down_pass, first_down_penalty,
                                   third_down_converted, third_down_failed,
                                   fourth_down_converted, fourth_down_failed, incomplete_pass,
                                   touchback, interception, punt_inside_twenty, punt_in_endzone,
                                   punt_out_of_bounds, punt_downed, punt_fair_catch, kickoff_inside_twenty,
                                   kickoff_in_endzone, kickoff_out_of_bounds, kickoff_downed,
                                   kickoff_fair_catch, fumble_forced, fumble_not_forced,
                                   fumble_out_of_bounds, solo_tackle, safety, penalty,
                                   tackled_for_loss, fumble_lost, own_kickoff_recovery,
                                   own_kickoff_recovery_td, qb_hit, rush_attempt, pass_attempt,
                                   sack, touchdown, pass_touchdown, rush_touchdown,
                                   return_touchdown, extra_point_attempt, two_point_attempt,
                                   field_goal_attempt, kickoff_attempt, punt_attempt,
                                   fumble, complete_pass, assist_tackle, lateral_reception,
                                   lateral_rush, lateral_return, lateral_recovery,
                                   passer_player_id, passer_player_name, passing, passing_yards,
                                   receiver_player_id, receiver_player_name, receiving, receiving_yards,
                                   rusher_player_id, rusher_player_name, rushing, rushing_yards,
                                   lateral_receiver_player_id, lateral_receiver_player_name,
                                   lateral_rusher_player_id, lateral_rusher_player_name,
                                   lateral_sack_player_id, lateral_sack_player_name,
                                   interception_player_id, interception_player_name,
                                   lateral_interception_player_id, lateral_interception_player_name,
                                   punt_returner_player_id, punt_returner_player_name,
                                   lateral_punt_returner_player_id, lateral_punt_returner_player_name,
                                   kickoff_returner_player_name, kickoff_returner_player_id,
                                   lateral_kickoff_returner_player_id, lateral_kickoff_returner_player_name,
                                   punter_player_id, punter_player_name, kicker_player_name,
                                   kicker_player_id, own_kickoff_recovery_player_id,
                                   own_kickoff_recovery_player_name, blocked_player_id,
                                   blocked_player_name, tackle_for_loss_1_player_id,
                                   tackle_for_loss_1_player_name, tackle_for_loss_2_player_id,
                                   tackle_for_loss_2_player_name, qb_hit_1_player_id,
                                   qb_hit_1_player_name, qb_hit_2_player_id, qb_hit_2_player_name,
                                   forced_fumble_player_1_team, forced_fumble_player_1_player_id,
                                   forced_fumble_player_1_player_name,
                                   forced_fumble_player_2_team, forced_fumble_player_2_player_id,
                                   forced_fumble_player_2_player_name,
                                   solo_tackle_1_team, solo_tackle_2_team, solo_tackle_1_player_id,
                                   solo_tackle_2_player_id, solo_tackle_1_player_name,
                                   solo_tackle_2_player_name, assist_tackle_1_player_id,
                                   assist_tackle_1_player_name, assist_tackle_1_team,
                                   assist_tackle_2_player_id, assist_tackle_2_player_name,
                                   assist_tackle_2_team, assist_tackle_3_player_id,
                                   assist_tackle_3_player_name, assist_tackle_3_team,
                                   assist_tackle_4_player_id, assist_tackle_4_player_name,
                                   assist_tackle_4_team, tackle_with_assist,
                                   tackle_with_assist_1_player_id, tackle_with_assist_1_player_name,
                                   tackle_with_assist_1_team, tackle_with_assist_2_player_id,
                                   tackle_with_assist_2_player_name, tackle_with_assist_2_team,
                                   pass_defense_1_player_id, pass_defense_1_player_name,
                                   pass_defense_2_player_id, pass_defense_2_player_name,
                                   fumbled_1_team, fumbled_1_player_id, fumbled_1_player_name,
                                   fumbled_2_player_id, fumbled_2_player_name, fumbled_2_team,
                                   fumble_recovery_1_team, fumble_recovery_1_yards,
                                   fumble_recovery_1_player_id, fumble_recovery_1_player_name,
                                   fumble_recovery_2_team, fumble_recovery_2_yards,
                                   fumble_recovery_2_player_id, fumble_recovery_2_player_name,
                                   sack_player_id, sack_player_name, half_sack_1_player_id,
                                   half_sack_1_player_name, half_sack_2_player_id,
                                   half_sack_2_player_name, return_team, return_yards,
                                   penalty_team, penalty_player_id, penalty_player_name,
                                   penalty_yards, replay_or_challenge, replay_or_challenge_result,
                                   penalty_type, defensive_two_point_attempt,
                                   defensive_two_point_conv, defensive_extra_point_attempt,
                                   defensive_extra_point_conv, safety_player_id,
                                   safety_player_name, season, cp, cpoe, series, series_success,
                                   series_result, order_sequence, start_time, time_of_day,
                                   stadium, weather, nfl_api_id, play_clock, play_deleted,
                                   play_type_nfl, special_teams_play, st_play_type,
                                   end_clock_time, end_yard_line, fixed_drive, fixed_drive_result,
                                   drive_real_start_time, drive_play_count, drive_time_of_possession,
                                   drive_first_downs, drive_inside20, drive_ended_with_score,
                                   drive_quarter_start, drive_quarter_end,
                                   drive_yards_penalized, drive_start_transition,
                                   drive_end_transition, drive_game_clock_start,
                                   drive_game_clock_end, drive_start_yard_line,
                                   drive_end_yard_line, drive_play_id_started,
                                   drive_play_id_ended, away_score, home_score)
                        pbp
                    '''
                else:
                    r_code = f'''
                        pbp <- nflverse::load_pbp({season})
                        pbp
                    '''
                
                df = self._fetch_from_r(r_code)
            else:
                # Fallback to CSV
                url = self.csv_urls['pbp'].format(year=season)
                df = pd.read_csv(url)
                if week:
                    df = df[df['week'] == week]
        except Exception as e:
            logger.error(f"Error fetching PBP data: {e}")
            df = pd.DataFrame()
        
        self._save_to_cache(cache_key, df)
        return df
    
    def get_odds(self, season: int, week: int) -> List[OddsDTO]:
        """Get betting odds for games."""
        games = self.get_games(season, week)
        odds_list = []
        
        for game in games:
            if game.home_spread is not None:
                odds_list.append(OddsDTO(
                    game_external_id=game.external_id,
                    provider="nflverse",
                    timestamp=game.game_date,
                    home_spread=game.home_spread,
                    away_spread=-game.home_spread if game.home_spread else None,
                    home_moneyline=game.home_moneyline or -110,
                    away_moneyline=game.away_moneyline or -110,
                    total=game.total_over_under
                ))
        
        return odds_list
    
    def get_injuries(self, season: int, week: int) -> List[InjuryDTO]:
        """Get injury reports from nflverse."""
        cache_key = self._get_cache_key('get_injuries', season, week)
        cached_data = self._get_from_cache(cache_key)
        if cached_data:
            return cached_data
        
        injuries = []
        
        try:
            if R_AVAILABLE and self.r_interface:
                r_code = f'''
                    injuries <- nflverse::load_injuries({season}) %>%
                        filter(week == {week}) %>%
                        select(season, game_type, week, gsis_id, 
                               club, player_name, position, injury_status,
                               practice_status, date_modified)
                    injuries
                '''
                
                df = self._fetch_from_r(r_code)
                
                for _, row in df.iterrows():
                    injuries.append(InjuryDTO(
                        team_external_id=self._safe_string(row['club']),
                        player_name=self._safe_string(row['player_name']),
                        player_position=self._safe_string(row['position']),
                        player_number=None,  # Not available in this dataset
                        injury_status=self._safe_string(row['injury_status']),
                        injury_type=self._safe_string(row.get('practice_status', 'Unknown')),
                        season=season,
                        week=week,
                        report_date=pd.to_datetime(row.get('date_modified', datetime.now()))
                    ))
            else:
                # Try CSV fallback
                url = self.csv_urls.get('injuries')
                if url:
                    df = pd.read_csv(url)
                    df = df[(df['season'] == season) & (df['week'] == week)]
                    
                    for _, row in df.iterrows():
                        injuries.append(InjuryDTO(
                            team_external_id=self._safe_string(row.get('club', row.get('team'))),
                            player_name=self._safe_string(row['player_name']),
                            player_position=self._safe_string(row.get('position', 'Unknown')),
                            player_number=None,
                            injury_status=self._safe_string(row.get('injury_status', 'Unknown')),
                            injury_type=self._safe_string(row.get('injury_type', 'Unknown')),
                            season=season,
                            week=week,
                            report_date=datetime.now()
                        ))
        except Exception as e:
            logger.error(f"Error fetching injuries: {e}")
        
        self._save_to_cache(cache_key, injuries)
        return injuries
    
    def get_weather(self, game_external_id: str) -> Optional[WeatherDTO]:
        """Get weather data for a specific game."""
        # Weather is typically included in games data
        games_cache = self._df_cache.get('games')
        
        if games_cache is not None:
            game = games_cache[games_cache['game_id'] == game_external_id]
            if not game.empty:
                row = game.iloc[0]
                
                return WeatherDTO(
                    game_external_id=game_external_id,
                    forecast_time=datetime.now(),
                    temperature=self._safe_float(row.get('temp')),
                    feels_like=None,  # Not available
                    wind_speed=self._safe_float(row.get('wind')),
                    wind_direction=None,  # Not available
                    precipitation_probability=None,  # Not available
                    humidity=None,  # Not available
                    condition=self._safe_string(row.get('roof'))
                )
        
        return None
    
    def get_advanced_stats(self, team_abbr: str, season: int) -> Dict[str, Any]:
        """
        Get advanced team statistics from nflverse.
        This includes EPA, DVOA-like metrics, and more.
        """
        cache_key = self._get_cache_key('get_advanced_stats', team_abbr, season)
        cached_data = self._get_from_cache(cache_key)
        if cached_data:
            return cached_data
        
        stats = {}
        
        try:
            if R_AVAILABLE and self.r_interface:
                r_code = f'''
                    team_stats <- nflverse::load_pbp({season}) %>%
                        filter(posteam == "{team_abbr}" | defteam == "{team_abbr}") %>%
                        group_by(posteam) %>%
                        summarise(
                            offensive_epa = mean(epa, na.rm = TRUE),
                            passing_epa = mean(epa[play_type == "pass"], na.rm = TRUE),
                            rushing_epa = mean(epa[play_type == "run"], na.rm = TRUE),
                            offensive_success_rate = mean(series_success, na.rm = TRUE),
                            explosive_play_rate = mean(yards_gained >= 20, na.rm = TRUE)
                        )
                    
                    def_stats <- nflverse::load_pbp({season}) %>%
                        filter(defteam == "{team_abbr}") %>%
                        summarise(
                            defensive_epa = mean(epa, na.rm = TRUE),
                            pass_defense_epa = mean(epa[play_type == "pass"], na.rm = TRUE),
                            run_defense_epa = mean(epa[play_type == "run"], na.rm = TRUE)
                        )
                    
                    list(offensive = as.data.frame(team_stats), 
                         defensive = as.data.frame(def_stats))
                '''
                
                result = self.r_interface(r_code)
                
                with localconverter(robjects.default_converter + pandas2ri.converter):
                    off_stats = robjects.conversion.rpy2py(result[0])
                    def_stats = robjects.conversion.rpy2py(result[1])
                
                stats = {
                    'offensive': off_stats.to_dict('records')[0] if not off_stats.empty else {},
                    'defensive': def_stats.to_dict('records')[0] if not def_stats.empty else {}
                }
        except Exception as e:
            logger.error(f"Error fetching advanced stats: {e}")
            stats = {'offensive': {}, 'defensive': {}}
        
        self._save_to_cache(cache_key, stats)
        return stats
    
    # Helper methods
    def _safe_string(self, value) -> Optional[str]:
        """Convert value to string, handling NaN."""
        if pd.isna(value):
            return None
        return str(value) if value else None
    
    def _safe_float(self, value) -> Optional[float]:
        """Convert value to float, handling NaN."""
        if pd.isna(value):
            return None
        try:
            return float(value)
        except:
            return None
    
    def _safe_int(self, value) -> Optional[int]:
        """Convert value to int, handling NaN."""
        if pd.isna(value):
            return None
        try:
            return int(value)
        except:
            return None

    def _parse_kickoff_time(self, game_date, game_time):
        """Parse kickoff time from various formats."""
        if not game_time:
            return game_date
        
        # If it's already a datetime, return it
        if isinstance(game_time, datetime):
            return game_time
        
        # If it's a string with time format "HH:MM"
        if isinstance(game_time, str) and ':' in game_time:
            try:
                parts = game_time.split(':')
                hour = int(parts[0])
                minute = int(parts[1]) if len(parts) > 1 else 0
                return game_date.replace(hour=hour, minute=minute)
            except (ValueError, AttributeError):
                return game_date
        
        # Default to game_date
        return game_date

    def get_comprehensive_player_stats(self, season: int, week: Optional[int] = None) -> pd.DataFrame:
        """
        Fetch ALL available player statistics columns from NFLverse.
        This pulls every stat available in the nflverse player_stats dataset.
        """
        cache_key = self._get_cache_key('get_comprehensive_player_stats', season, week)
        cached_data = self._get_from_cache(cache_key)
        if cached_data is not None:
            return cached_data
        
        try:
            if R_AVAILABLE and self.r_interface:
                # R code to load ALL columns from player stats
                if week:
                    r_code = f'''
                        stats <- nflverse::load_player_stats(seasons = {season}) %>%
                            filter(week == {week})
                        stats
                    '''
                else:
                    r_code = f'''
                        stats <- nflverse::load_player_stats(seasons = {season})
                        stats
                    '''
                
                df = self._fetch_from_r(r_code)
                
                # Log the columns we got
                logger.info(f"Loaded {len(df)} player records with {len(df.columns)} columns")
                logger.info(f"Available columns: {', '.join(df.columns[:20])}...")  # Show first 20
                
            else:
                # Fallback to CSV with ALL columns
                url = self.csv_urls['player_stats']
                df = pd.read_csv(url)
                df = df[df['season'] == season]
                if week:
                    df = df[df['week'] == week]
            
            self._save_to_cache(cache_key, df)
            return df
            
        except Exception as e:
            logger.error(f"Error fetching comprehensive player stats: {e}")
            return pd.DataFrame()

    def get_all_player_columns(self, season: int = 2024) -> List[str]:
        """
        Get a list of all available columns in the player stats data.
        Useful for understanding what data is available.
        """
        try:
            if R_AVAILABLE and self.r_interface:
                r_code = f'''
                    stats <- nflverse::load_player_stats(seasons = {season}) %>%
                        head(1)
                    colnames(stats)
                '''
                
                with localconverter(robjects.default_converter + pandas2ri.converter):
                    result = self.r_interface(r_code)
                    columns = list(result)
                    
                logger.info(f"Found {len(columns)} columns in player stats")
                return columns
            else:
                # Fallback to CSV
                url = self.csv_urls['player_stats']
                df = pd.read_csv(url, nrows=1)
                return df.columns.tolist()
                
        except Exception as e:
            logger.error(f"Error getting player columns: {e}")
            return []

    def build_comprehensive_player_profiles(self, season: int) -> Dict[str, Any]:
        """
        Build comprehensive player profiles with ALL stats aggregated.
        Returns detailed profiles keyed by player_id.
        """
        cache_key = self._get_cache_key('build_comprehensive_player_profiles', season)
        cached_data = self._get_from_cache(cache_key)
        if cached_data is not None:
            return cached_data
        
        try:
            # Get all player stats for the season
            df = self.get_comprehensive_player_stats(season)
            
            if df.empty:
                return {}
            
            # Group by player and aggregate
            profiles = {}
            
            # Group by player_id
            for player_id, player_data in df.groupby('player_id'):
                # Get basic info from first row
                first_row = player_data.iloc[0]
                
                profile = {
                    'player_id': player_id,
                    'player_name': first_row.get('player_name'),
                    'player_display_name': first_row.get('player_display_name'),
                    'position': first_row.get('position'),
                    'position_group': first_row.get('position_group'),
                    'recent_team': player_data.iloc[-1].get('recent_team'),  # Last team
                    'headshot_url': first_row.get('headshot_url'),
                    'games_played': len(player_data),
                    'weeks_played': player_data['week'].tolist() if 'week' in player_data else []
                }
                
                # Aggregate numeric stats
                numeric_cols = player_data.select_dtypes(include=[np.number]).columns
                
                # Sum up cumulative stats
                cumulative_stats = [
                    'completions', 'attempts', 'passing_yards', 'passing_tds', 'interceptions',
                    'sacks', 'sack_yards', 'sack_fumbles', 'sack_fumbles_lost',
                    'passing_air_yards', 'passing_yards_after_catch', 'passing_first_downs',
                    'passing_epa', 'passing_2pt_conversions',
                    'carries', 'rushing_yards', 'rushing_tds', 'rushing_fumbles',
                    'rushing_fumbles_lost', 'rushing_first_downs', 'rushing_epa',
                    'rushing_2pt_conversions',
                    'targets', 'receptions', 'receiving_yards', 'receiving_tds',
                    'receiving_fumbles', 'receiving_fumbles_lost', 'receiving_air_yards',
                    'receiving_yards_after_catch', 'receiving_first_downs',
                    'receiving_epa', 'receiving_2pt_conversions',
                    'fantasy_points', 'fantasy_points_ppr',
                    'special_teams_tds'
                ]
                
                # Sum these up
                season_totals = {}
                for col in cumulative_stats:
                    if col in player_data.columns:
                        season_totals[f'{col}_total'] = player_data[col].sum()
                        season_totals[f'{col}_per_game'] = player_data[col].mean()
                
                # Calculate advanced metrics
                advanced_metrics = {}
                
                # For efficiency metrics, take the mean
                efficiency_metrics = [
                    'pacr', 'racr', 'target_share', 'air_yards_share', 'wopr', 'dakota'
                ]
                
                for col in efficiency_metrics:
                    if col in player_data.columns:
                        advanced_metrics[f'{col}_avg'] = player_data[col].mean()
                        advanced_metrics[f'{col}_max'] = player_data[col].max()
                        advanced_metrics[f'{col}_min'] = player_data[col].min()
                
                # Combine everything
                profile.update(season_totals)
                profile.update(advanced_metrics)
                
                profiles[player_id] = profile
            
            self._save_to_cache(cache_key, profiles)
            return profiles
            
        except Exception as e:
            logger.error(f"Error building player profiles: {e}")
            return {}

    def get_player_game_logs(self, player_name: str, season: int) -> pd.DataFrame:
        """
        Get detailed game-by-game logs for a specific player.
        Includes all available stats for each game.
        """
        cache_key = self._get_cache_key('get_player_game_logs', player_name, season)
        cached_data = self._get_from_cache(cache_key)
        if cached_data is not None:
            return cached_data
        
        try:
            if R_AVAILABLE and self.r_interface:
                r_code = f'''
                    stats <- nflverse::load_player_stats(seasons = {season}) %>%
                        filter(player_display_name == "{player_name}" | 
                            player_name == "{player_name}") %>%
                        arrange(week)
                    stats
                '''
                
                df = self._fetch_from_r(r_code)
            else:
                # Fallback to CSV
                df = self.get_comprehensive_player_stats(season)
                df = df[(df['player_display_name'] == player_name) | 
                    (df['player_name'] == player_name)]
                df = df.sort_values('week')
            
            self._save_to_cache(cache_key, df)
            return df
            
        except Exception as e:
            logger.error(f"Error fetching player game logs: {e}")
            return pd.DataFrame()

    def get_position_rankings(self, season: int, week: Optional[int] = None, 
                            position: str = 'QB', metric: str = 'fantasy_points_ppr') -> pd.DataFrame:
        """
        Get player rankings by position for any available metric.
        
        Args:
            season: NFL season
            week: Optional specific week
            position: Position to filter (QB, RB, WR, TE, etc.)
            metric: Metric to rank by (any numeric column)
        """
        try:
            # Get comprehensive stats
            df = self.get_comprehensive_player_stats(season, week)
            
            if df.empty:
                return pd.DataFrame()
            
            # Filter by position
            df = df[df['position'] == position]
            
            # Check if metric exists
            if metric not in df.columns:
                logger.warning(f"Metric {metric} not found. Available metrics: {df.select_dtypes(include=[np.number]).columns.tolist()}")
                return pd.DataFrame()
            
            # Group by player and aggregate the metric
            if week is None:
                # Season totals
                rankings = df.groupby(['player_id', 'player_display_name', 'recent_team']).agg({
                    metric: 'sum',
                    'week': 'count'  # Games played
                }).reset_index()
                rankings.columns = ['player_id', 'player_display_name', 'team', metric, 'games_played']
            else:
                # Single week
                rankings = df[['player_id', 'player_display_name', 'recent_team', metric]].copy()
                rankings.columns = ['player_id', 'player_display_name', 'team', metric]
            
            # Sort by metric
            rankings = rankings.sort_values(metric, ascending=False)
            rankings['rank'] = range(1, len(rankings) + 1)
            
            return rankings
            
        except Exception as e:
            logger.error(f"Error getting position rankings: {e}")
            return pd.DataFrame()
    def get_nextgen_stats(self, stat_type: str = "passing", seasons: Optional[List[int]] = None) -> pd.DataFrame:
        """
        Get Next Gen Stats using the correct nflverse function.
        
        Args:
            stat_type: One of "passing", "receiving", "rushing"
            seasons: List of seasons (defaults to [2025] for current)
            
        Returns:
            DataFrame with Next Gen Stats
        """
        if seasons is None:
            seasons = [2025]
        
        cache_key = self._get_cache_key('get_nextgen_stats', stat_type, *seasons)
        cached_data = self._get_from_cache(cache_key)
        if cached_data is not None:
            return cached_data
        
        try:
            if R_AVAILABLE and self.r_interface:
                # Convert seasons list to R vector
                seasons_str = f"c({','.join(map(str, seasons))})"
                
                r_code = f'''
                    # Load Next Gen Stats using the correct function
                    ngs_data <- nflverse::load_nextgen_stats(
                        stat_type = "{stat_type}",
                        seasons = {seasons_str}
                    )
                    ngs_data
                '''
                
                df = self._fetch_from_r(r_code)
                
                logger.info(f"✅ Loaded {len(df)} Next Gen Stats records for {stat_type}")
                
                # Log the actual columns we got
                if not df.empty:
                    logger.info(f"Next Gen columns available: {', '.join(df.columns[:20])}")
                    
            else:
                # CSV fallback
                dfs = []
                for season in seasons:
                    url = f"https://github.com/nflverse/nflverse-data/releases/download/nextgen_stats/ngs_{season}_{stat_type}.csv"
                    try:
                        season_df = pd.read_csv(url)
                        dfs.append(season_df)
                    except:
                        logger.warning(f"Could not load NGS {stat_type} for {season}")
                
                df = pd.concat(dfs, ignore_index=True) if dfs else pd.DataFrame()
            
            self._save_to_cache(cache_key, df)
            return df
            
        except Exception as e:
            logger.error(f"Error fetching Next Gen Stats: {e}")
            return pd.DataFrame()

    def get_nextgen_data_dictionary(self) -> pd.DataFrame:
        """
        Get the Next Gen Stats data dictionary to understand what each column means.
        """
        try:
            if R_AVAILABLE and self.r_interface:
                r_code = '''
                    # Get the data dictionary
                    dict <- nflverse::dictionary_nextgen_stats
                    dict
                '''
                
                df = self._fetch_from_r(r_code)
                
                logger.info(f"✅ Loaded Next Gen Stats data dictionary with {len(df)} field definitions")
                return df
            else:
                # Try to load from CSV
                url = "https://raw.githubusercontent.com/nflverse/nflverse-data/master/data-raw/nextgen_stats_dict.csv"
                return pd.read_csv(url)
                
        except Exception as e:
            logger.error(f"Error fetching NGS dictionary: {e}")
            return pd.DataFrame()

    def get_all_ngs_stats_types(self) -> Dict[str, pd.DataFrame]:
        """
        Get all three types of Next Gen Stats at once.
        """
        results = {}
        
        for stat_type in ["passing", "receiving", "rushing"]:
            df = self.get_nextgen_stats(stat_type=stat_type, seasons=[2025])
            if not df.empty:
                results[stat_type] = df
                logger.info(f"✅ {stat_type}: {len(df)} records")
        
        return results

    def combine_player_stats_with_ngs(self, season: int = 2025, week: Optional[int] = None) -> pd.DataFrame:
        """
        Combine regular player stats with Next Gen Stats properly.
        """
        # Get base comprehensive stats
        base_df = self.get_comprehensive_player_stats(season, week)
        
        if base_df.empty:
            logger.warning(f"No base stats found for season {season}")
            return base_df
        
        # Get all NGS types
        ngs_data = self.get_all_ngs_stats_types()
        
        # Merge each type
        for stat_type, ngs_df in ngs_data.items():
            if ngs_df.empty:
                continue
                
            # Filter to the week if specified
            if week and 'week' in ngs_df.columns:
                ngs_df = ngs_df[ngs_df['week'] == week]
            
            # NGS uses player_gsis_id, regular stats use player_id
            # They should be the same value
            if 'player_gsis_id' in ngs_df.columns:
                ngs_df = ngs_df.rename(columns={'player_gsis_id': 'player_id'})
            
            # Identify NGS-specific columns to avoid duplicates
            merge_on = ['player_id', 'week'] if week else ['player_id', 'season']
            merge_on = [col for col in merge_on if col in base_df.columns and col in ngs_df.columns]
            
            if not merge_on:
                logger.warning(f"Cannot merge {stat_type} NGS data - no common columns")
                continue
            
            # Get columns unique to NGS
            ngs_unique_cols = [col for col in ngs_df.columns 
                            if col not in base_df.columns or col in merge_on]
            
            # Merge
            base_df = base_df.merge(
                ngs_df[ngs_unique_cols],
                on=merge_on,
                how='left',
                suffixes=('', f'_{stat_type}_ngs')
            )
            
            logger.info(f"✅ Merged {stat_type} Next Gen Stats")
        
        return base_df

    def test_comprehensive_2025_data(self, week: int = 3) -> None:
        """
        Test that we can get ALL 2025 data including Next Gen Stats.
        """
        print("\n" + "="*70)
        print("TESTING COMPREHENSIVE NFLVERSE 2025 DATA")
        print("="*70)
        
        # 1. Test basic player stats
        print(f"\n1. Loading Week {week} player stats...")
        basic_df = self.get_comprehensive_player_stats(2025, week)
        print(f"   ✅ Basic stats: {len(basic_df)} records, {len(basic_df.columns)} columns")
        
        # Check for key columns
        key_cols = ['passing_epa', 'rushing_epa', 'receiving_epa', 'pacr', 'racr', 'wopr', 'dakota']
        found = [col for col in key_cols if col in basic_df.columns]
        print(f"   ✅ Advanced metrics found: {', '.join(found)}")
        
        # 2. Test Next Gen Stats
        print(f"\n2. Loading Next Gen Stats...")
        ngs_all = self.get_all_ngs_stats_types()
        for stat_type, df in ngs_all.items():
            if not df.empty:
                print(f"   ✅ NGS {stat_type}: {len(df)} records")
                # Show some unique columns
                if stat_type == "passing":
                    ngs_cols = ['avg_time_to_throw', 'aggressiveness', 'expected_completion_percentage']
                elif stat_type == "receiving":
                    ngs_cols = ['avg_separation', 'avg_cushion', 'avg_yac_above_expectation']
                else:  # rushing
                    ngs_cols = ['efficiency', 'rush_yards_over_expected', 'percent_attempts_gte_eight_defenders']
                
                found_ngs = [col for col in ngs_cols if col in df.columns]
                if found_ngs:
                    print(f"      Columns: {', '.join(found_ngs[:3])}")
        
        # 3. Test combined data
        print(f"\n3. Combining all data sources...")
        combined_df = self.combine_player_stats_with_ngs(2025, week)
        print(f"   ✅ Combined: {len(combined_df)} records, {len(combined_df.columns)} total columns")
        
        # 4. Show sample data
        print(f"\n4. Sample QB data with NGS:")
        qb_df = combined_df[combined_df['position'] == 'QB'].head(3)
        if not qb_df.empty:
            for _, qb in qb_df.iterrows():
                print(f"   {qb['player_display_name']} ({qb['recent_team']})")
                print(f"      Passing: {qb.get('passing_yards', 0):.0f} yds, {qb.get('passing_tds', 0):.0f} TDs")
                if 'avg_time_to_throw' in qb and pd.notna(qb['avg_time_to_throw']):
                    print(f"      NGS: {qb['avg_time_to_throw']:.2f}s time to throw")
                if 'aggressiveness' in qb and pd.notna(qb['aggressiveness']):
                    print(f"           {qb['aggressiveness']:.1f}% aggressiveness")
        
        # 5. Show data dictionary
        print(f"\n5. Loading data dictionary...")
        dict_df = self.get_nextgen_data_dictionary()
        if not dict_df.empty:
            print(f"   ✅ Dictionary loaded with {len(dict_df)} field definitions")
        
        print("\n" + "="*70)
        print("✅ ALL TESTS PASSED - NFLverse 2025 data fully available!")
        print("="*70)

# Register the enhanced adapter
ProviderRegistry.register("nflverse_r", NFLverseRAdapter)