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
        logger.info("Loading nflverse data in R...")
        self.r_interface('nflverse::load_pbp(seasons = 2020:2024)')
        self.r_interface('nflverse::load_player_stats(seasons = 2020:2024)')
        self.r_interface('nflverse::load_rosters(seasons = 2020:2024)')
    
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

# Register the enhanced adapter
ProviderRegistry.register("nflverse_r", NFLverseRAdapter)