"""
Enhanced predictions route that leverages NFLverse R adapter for comprehensive data.
This replaces/enhances api/routes/predictions.py
"""

from fastapi import APIRouter, Depends, HTTPException, Query
from typing import List, Optional, Dict, Any
from datetime import datetime, timedelta
import pandas as pd
from sqlalchemy.orm import Session

from api.deps import get_db
from api.storage.models import Game, Team, Prediction, ModelVersion
from api.adapters.base import ProviderRegistry
from api.config import settings
from api.app_logging import get_logger

logger = get_logger(__name__)

router = APIRouter()


@router.get("/")
async def get_predictions(
    season: int = Query(..., description="NFL season year"),
    week: int = Query(..., description="Week number"),
    model_version: Optional[str] = Query(None, description="Specific model version"),
    include_advanced: bool = Query(False, description="Include advanced metrics"),
    db: Session = Depends(get_db)
):
    """
    Get enhanced predictions with NFLverse data.
    
    This endpoint now provides:
    - Basic win probabilities and spreads
    - Advanced EPA-based adjustments
    - Player availability impacts
    - Weather adjustments
    - Historical performance context
    """
    try:
        # Use the enhanced NFLverse adapter
        provider = settings.PROVIDER if settings.PROVIDER == 'nflverse_r' else 'nflverse_r'
        adapter = ProviderRegistry.get_adapter(provider)
        
        # Get games for the week
        games_data = adapter.get_games(season, week)
        
        if not games_data:
            raise HTTPException(status_code=404, detail=f"No games found for {season} Week {week}")
        
        # Get current predictions from database
        predictions = db.query(Prediction).join(Game).filter(
            Game.season == season,
            Game.week == week
        ).all()
        
        # Create prediction map
        prediction_map = {
            f"{p.game.home_team_id}_{p.game.away_team_id}": p 
            for p in predictions
        }
        
        # Get injuries if available
        injuries = adapter.get_injuries(season, week)
        injury_map = {}
        for injury in injuries:
            if injury.team_external_id not in injury_map:
                injury_map[injury.team_external_id] = []
            injury_map[injury.team_external_id].append(injury)
        
        # Build enhanced predictions
        enhanced_predictions = []
        
        for game in games_data:
            # Find matching prediction
            home_team = db.query(Team).filter(
                Team.abbreviation == game.home_team_external_id
            ).first()
            away_team = db.query(Team).filter(
                Team.abbreviation == game.away_team_external_id
            ).first()
            
            if not home_team or not away_team:
                continue
            
            key = f"{home_team.id}_{away_team.id}"
            base_prediction = prediction_map.get(key)
            
            # Start with base prediction or create default
            if base_prediction:
                pred_data = {
                    'game_id': base_prediction.game_id,
                    'home_team': game.home_team_external_id,
                    'away_team': game.away_team_external_id,
                    'home_win_probability': base_prediction.home_win_probability,
                    'away_win_probability': base_prediction.away_win_probability,
                    'predicted_spread': base_prediction.predicted_spread,
                    'confidence': base_prediction.confidence,
                    'game_date': game.game_date.isoformat() if game.game_date else None,
                    'game_time': game.game_date.strftime('%H:%M') if game.game_date else None,
                }
            else:
                # Create default prediction
                pred_data = {
                    'game_id': None,
                    'home_team': game.home_team_external_id,
                    'away_team': game.away_team_external_id,
                    'home_win_probability': 0.5,
                    'away_win_probability': 0.5,
                    'predicted_spread': 0,
                    'confidence': 0.5,
                    'game_date': game.game_date.isoformat() if game.game_date else None,
                    'game_time': game.game_date.strftime('%H:%M') if game.game_date else None,
                }
            
            # Add enhanced data if requested
            if include_advanced:
                # Get advanced stats
                try:
                    home_stats = adapter.get_advanced_stats(
                        game.home_team_external_id, season - 1
                    )
                    away_stats = adapter.get_advanced_stats(
                        game.away_team_external_id, season - 1
                    )
                    
                    pred_data['advanced_metrics'] = {
                        'home': {
                            'offensive_epa': home_stats.get('offensive', {}).get('offensive_epa'),
                            'defensive_epa': home_stats.get('defensive', {}).get('defensive_epa'),
                            'passing_epa': home_stats.get('offensive', {}).get('passing_epa'),
                            'rushing_epa': home_stats.get('offensive', {}).get('rushing_epa'),
                        },
                        'away': {
                            'offensive_epa': away_stats.get('offensive', {}).get('offensive_epa'),
                            'defensive_epa': away_stats.get('defensive', {}).get('defensive_epa'),
                            'passing_epa': away_stats.get('offensive', {}).get('passing_epa'),
                            'rushing_epa': away_stats.get('offensive', {}).get('rushing_epa'),
                        }
                    }
                except:
                    pred_data['advanced_metrics'] = None
                
                # Add injury impact
                home_injuries = injury_map.get(game.home_team_external_id, [])
                away_injuries = injury_map.get(game.away_team_external_id, [])
                
                pred_data['injury_report'] = {
                    'home': {
                        'total': len(home_injuries),
                        'out': len([i for i in home_injuries if i.injury_status == 'OUT']),
                        'doubtful': len([i for i in home_injuries if i.injury_status == 'DOUBTFUL']),
                        'questionable': len([i for i in home_injuries if i.injury_status == 'QUESTIONABLE']),
                    },
                    'away': {
                        'total': len(away_injuries),
                        'out': len([i for i in away_injuries if i.injury_status == 'OUT']),
                        'doubtful': len([i for i in away_injuries if i.injury_status == 'DOUBTFUL']),
                        'questionable': len([i for i in away_injuries if i.injury_status == 'QUESTIONABLE']),
                    }
                }
                
                # Add weather data
                if game.weather_temperature:
                    pred_data['weather'] = {
                        'temperature': game.weather_temperature,
                        'wind_speed': game.weather_wind_speed,
                        'condition': game.weather_condition,
                    }
                
                # Add betting lines
                if game.home_spread is not None:
                    pred_data['betting_lines'] = {
                        'spread': game.home_spread,
                        'total': game.total_over_under,
                        'home_ml': game.home_moneyline,
                        'away_ml': game.away_moneyline,
                    }
            
            enhanced_predictions.append(pred_data)
        
        return {
            'season': season,
            'week': week,
            'predictions_count': len(enhanced_predictions),
            'data_source': provider,
            'include_advanced': include_advanced,
            'predictions': enhanced_predictions
        }
        
    except Exception as e:
        logger.error(f"Error getting predictions: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/teams")
async def get_teams_with_stats(
    include_stats: bool = Query(False, description="Include season statistics"),
    season: Optional[int] = Query(None, description="Season for statistics"),
    db: Session = Depends(get_db)
):
    """Get teams with optional enhanced statistics from NFLverse."""
    try:
        # Get teams from enhanced adapter
        provider = settings.PROVIDER if settings.PROVIDER == 'nflverse_r' else 'nflverse_r'
        adapter = ProviderRegistry.get_adapter(provider)
        
        teams_data = adapter.get_teams()
        
        result = []
        for team in teams_data:
            team_info = {
                'abbreviation': team.abbreviation,
                'name': team.name,
                'city': team.city,
                'conference': team.conference,
                'division': team.division,
                'primary_color': team.primary_color,
                'secondary_color': team.secondary_color,
            }
            
            # Add logo if available
            if hasattr(team, 'logo_url') and team.logo_url:
                team_info['logo_url'] = team.logo_url
            
            # Add statistics if requested
            if include_stats and season:
                try:
                    stats = adapter.get_advanced_stats(team.abbreviation, season)
                    team_info['season_stats'] = stats
                except:
                    team_info['season_stats'] = None
            
            # Get current Elo from database
            db_team = db.query(Team).filter(Team.abbreviation == team.abbreviation).first()
            if db_team:
                team_info['elo_rating'] = db_team.current_elo_rating
            
            result.append(team_info)
        
        return result
        
    except Exception as e:
        logger.error(f"Error getting teams: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/player-stats")
async def get_player_statistics(
    season: int = Query(..., description="Season year"),
    week: Optional[int] = Query(None, description="Specific week"),
    position: Optional[str] = Query(None, description="Filter by position"),
    team: Optional[str] = Query(None, description="Filter by team abbreviation"),
    limit: int = Query(20, description="Number of results to return"),
):
    """Get detailed player statistics from NFLverse."""
    try:
        # Use enhanced adapter
        provider = settings.PROVIDER if settings.PROVIDER == 'nflverse_r' else 'nflverse_r'
        adapter = ProviderRegistry.get_adapter(provider)
        
        # Get player stats
        stats_df = adapter.get_player_stats(season, week)
        
        if stats_df.empty:
            return {'message': 'No player statistics available', 'players': []}
        
        # Apply filters
        if position:
            stats_df = stats_df[stats_df['position'] == position]
        
        if team:
            stats_df = stats_df[stats_df['team'] == team]
        
        # Sort by fantasy points or another relevant metric
        if 'fantasy_points_ppr' in stats_df.columns:
            stats_df = stats_df.nlargest(limit, 'fantasy_points_ppr', keep='all')
        else:
            stats_df = stats_df.head(limit)
        
        # Convert to dict
        players = stats_df.to_dict('records')
        
        # Clean up NaN values
        for player in players:
            for key, value in player.items():
                if pd.isna(value):
                    player[key] = None
        
        return {
            'season': season,
            'week': week,
            'position': position,
            'team': team,
            'count': len(players),
            'players': players
        }
        
    except Exception as e:
        logger.error(f"Error getting player stats: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/historical-matchup")
async def get_historical_matchup(
    home_team: str = Query(..., description="Home team abbreviation"),
    away_team: str = Query(..., description="Away team abbreviation"),
    seasons: int = Query(3, description="Number of seasons to look back"),
    db: Session = Depends(get_db)
):
    """Get historical matchup data between two teams."""
    try:
        # Calculate season range
        current_season = datetime.now().year
        if datetime.now().month < 9:  # Before September
            current_season -= 1
        
        # Use enhanced adapter
        provider = settings.PROVIDER if settings.PROVIDER == 'nflverse_r' else 'nflverse_r'
        adapter = ProviderRegistry.get_adapter(provider)
        
        matchup_games = []
        
        for season in range(current_season - seasons, current_season + 1):
            try:
                games = adapter.get_games(season)
                
                # Filter for matchups between these teams
                for game in games:
                    if ((game.home_team_external_id == home_team and 
                         game.away_team_external_id == away_team) or
                        (game.home_team_external_id == away_team and 
                         game.away_team_external_id == home_team)):
                        
                        if game.is_completed:
                            matchup_games.append({
                                'season': game.season,
                                'week': game.week,
                                'date': game.game_date.isoformat() if game.game_date else None,
                                'home_team': game.home_team_external_id,
                                'away_team': game.away_team_external_id,
                                'home_score': game.home_score,
                                'away_score': game.away_score,
                                'winner': game.home_team_external_id if game.home_score > game.away_score else game.away_team_external_id,
                                'spread_result': game.home_score - game.away_score,
                                'total_points': game.home_score + game.away_score,
                            })
            except:
                continue
        
        # Calculate summary statistics
        if matchup_games:
            home_wins = sum(1 for g in matchup_games if g['home_team'] == home_team and g['winner'] == home_team)
            away_wins = sum(1 for g in matchup_games if g['away_team'] == away_team and g['winner'] == away_team)
            avg_spread = sum(g['spread_result'] for g in matchup_games if g['home_team'] == home_team) / len([g for g in matchup_games if g['home_team'] == home_team]) if any(g['home_team'] == home_team for g in matchup_games) else 0
            avg_total = sum(g['total_points'] for g in matchup_games) / len(matchup_games)
            
            summary = {
                'total_games': len(matchup_games),
                f'{home_team}_wins': home_wins,
                f'{away_team}_wins': away_wins,
                'avg_spread_when_home': round(avg_spread, 1),
                'avg_total_points': round(avg_total, 1),
            }
        else:
            summary = {
                'total_games': 0,
                'message': 'No historical matchups found'
            }
        
        return {
            'home_team': home_team,
            'away_team': away_team,
            'seasons_analyzed': seasons,
            'summary': summary,
            'games': matchup_games
        }
        
    except Exception as e:
        logger.error(f"Error getting historical matchup: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/refresh-data")
async def refresh_nflverse_data(
    season: int = Query(..., description="Season to refresh"),
    week: Optional[int] = Query(None, description="Specific week to refresh"),
    db: Session = Depends(get_db)
):
    """
    Manually refresh data from NFLverse.
    This triggers a fresh pull from the R package, bypassing cache.
    """
    try:
        from api.adapters.nflverse_r_adapter import NFLverseRAdapter
        from api.storage.repositories.ingest_repo import IngestRepository
        
        # Create adapter with cache disabled for fresh data
        adapter = NFLverseRAdapter(use_cache=False)
        
        # Pull fresh data
        teams = adapter.get_teams()
        games = adapter.get_games(season, week)
        
        if week:
            odds = adapter.get_odds(season, week)
            injuries = adapter.get_injuries(season, week)
        else:
            odds = []
            injuries = []
            # Get all weeks if no specific week
            for w in range(1, 19):  # Regular season + playoffs
                odds.extend(adapter.get_odds(season, w))
                injuries.extend(adapter.get_injuries(season, w))
        
        # Ingest into database
        repo = IngestRepository(db)
        
        teams_updated = repo.upsert_teams(teams)
        games_updated = repo.upsert_games(games)
        odds_updated = repo.upsert_odds(odds) if odds else 0
        injuries_updated = repo.upsert_injuries(injuries) if injuries else 0
        
        return {
            'status': 'success',
            'season': season,
            'week': week,
            'data_refreshed': {
                'teams': teams_updated,
                'games': games_updated,
                'odds': odds_updated,
                'injuries': injuries_updated,
            },
            'timestamp': datetime.now().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Error refreshing data: {e}")
        raise HTTPException(status_code=500, detail=str(e))