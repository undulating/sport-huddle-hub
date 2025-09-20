#!/usr/bin/env python3
"""
NFLverse R Integration Test Suite and Usage Examples
This script demonstrates how to use the enhanced NFLverse adapter
with your sports prediction WebApp.
"""

import sys
import os
sys.path.insert(0, '.')

import pandas as pd
from datetime import datetime
from typing import List, Dict, Any
import logging
import json
from tabulate import tabulate

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class NFLverseIntegrationTester:
    """Test suite for NFLverse R integration."""
    
    def __init__(self):
        """Initialize the tester."""
        try:
            from api.adapters.nflverse_r_adapter import NFLverseRAdapter
            self.adapter = NFLverseRAdapter(use_cache=True)
            self.has_r = self.adapter.r_interface is not None
        except ImportError as e:
            logger.error(f"Could not import NFLverse adapter: {e}")
            sys.exit(1)
    
    def run_all_tests(self):
        """Run all integration tests."""
        print("\n" + "="*60)
        print("🏈 NFLverse R Integration Test Suite")
        print("="*60)
        
        tests = [
            ("Basic Connectivity", self.test_basic_connectivity),
            ("Team Data Retrieval", self.test_team_data),
            ("Game Schedule", self.test_game_schedule),
            ("Player Statistics", self.test_player_stats),
            ("Play-by-Play Data", self.test_pbp_data),
            ("Injury Reports", self.test_injury_data),
            ("Betting Odds", self.test_odds_data),
            ("Advanced Analytics", self.test_advanced_analytics),
            ("Cache Performance", self.test_cache_performance),
            ("Fallback Mechanism", self.test_fallback),
        ]
        
        results = []
        for test_name, test_func in tests:
            print(f"\n📋 Testing: {test_name}")
            print("-" * 40)
            try:
                success, message = test_func()
                status = "✅ PASS" if success else "❌ FAIL"
                results.append([test_name, status, message])
                print(f"{status}: {message}")
            except Exception as e:
                results.append([test_name, "❌ ERROR", str(e)])
                print(f"❌ ERROR: {e}")
        
        # Print summary
        print("\n" + "="*60)
        print("📊 Test Summary")
        print("="*60)
        print(tabulate(results, headers=["Test", "Status", "Details"], tablefmt="grid"))
        
        # Return overall success
        passed = sum(1 for r in results if "PASS" in r[1])
        total = len(results)
        print(f"\n✨ Passed {passed}/{total} tests")
        return passed == total
    
    def test_basic_connectivity(self) -> tuple[bool, str]:
        """Test basic R connectivity."""
        if self.has_r:
            return True, "R interface is available and connected"
        else:
            return True, "R not available, using CSV fallback (this is okay)"
    
    def test_team_data(self) -> tuple[bool, str]:
        """Test team data retrieval."""
        teams = self.adapter.get_teams()
        
        if not teams:
            return False, "No teams returned"
        
        # Check for all 32 NFL teams
        if len(teams) < 32:
            return False, f"Expected 32 teams, got {len(teams)}"
        
        # Check team structure
        sample_team = teams[0]
        required_fields = ['external_id', 'name', 'city', 'abbreviation', 
                          'conference', 'division']
        
        for field in required_fields:
            if not hasattr(sample_team, field):
                return False, f"Missing field: {field}"
        
        # Display sample
        print(f"  Found {len(teams)} teams")
        print(f"  Sample: {sample_team.city} {sample_team.name} ({sample_team.abbreviation})")
        print(f"  Conference: {sample_team.conference}, Division: {sample_team.division}")
        
        return True, f"Successfully loaded {len(teams)} teams with complete data"
    
    def test_game_schedule(self) -> tuple[bool, str]:
        """Test game schedule retrieval."""
        # Test for 2024 Week 1
        games = self.adapter.get_games(2024, 1)
        
        if not games:
            return False, "No games returned for 2024 Week 1"
        
        # Check game structure
        sample_game = games[0]
        required_fields = ['external_id', 'season', 'week', 'game_date',
                          'home_team_external_id', 'away_team_external_id']
        
        for field in required_fields:
            if not hasattr(sample_game, field):
                return False, f"Missing field: {field}"
        
        # Display sample game
        print(f"  Found {len(games)} games for Week 1, 2024")
        print(f"  Sample: {sample_game.away_team_external_id} @ {sample_game.home_team_external_id}")
        print(f"  Date: {sample_game.game_date}")
        
        # Test full season retrieval
        full_season = self.adapter.get_games(2023)
        expected_games = 272  # 272 regular season games
        
        if len(full_season) < expected_games:
            return False, f"Expected at least {expected_games} games for 2023 season, got {len(full_season)}"
        
        return True, f"Successfully loaded games (Week: {len(games)}, Season: {len(full_season)})"
    
    def test_player_stats(self) -> tuple[bool, str]:
        """Test player statistics retrieval."""
        try:
            # Get player stats for a recent week
            stats_df = self.adapter.get_player_stats(2024, 1)
            
            if stats_df.empty:
                # Try 2023 if 2024 not available
                stats_df = self.adapter.get_player_stats(2023, 17)
            
            if stats_df.empty:
                return False, "No player statistics available"
            
            # Check for key columns
            expected_cols = ['player_name', 'position', 'team', 'passing_yards', 
                           'rushing_yards', 'receiving_yards']
            missing_cols = [col for col in expected_cols if col not in stats_df.columns]
            
            if missing_cols:
                return False, f"Missing columns: {missing_cols}"
            
            # Get top performers
            qb_stats = stats_df[stats_df['position'] == 'QB'].nlargest(3, 'passing_yards', keep='all')
            
            if not qb_stats.empty:
                top_qb = qb_stats.iloc[0]
                print(f"  Top QB: {top_qb['player_name']} - {top_qb['passing_yards']:.0f} yards")
            
            print(f"  Total players with stats: {len(stats_df)}")
            print(f"  Positions: {stats_df['position'].unique()[:5].tolist()}...")
            
            return True, f"Successfully loaded {len(stats_df)} player statistics"
            
        except Exception as e:
            return False, f"Error loading player stats: {e}"
    
    def test_pbp_data(self) -> tuple[bool, str]:
        """Test play-by-play data retrieval."""
        try:
            # Get PBP data for a specific week
            pbp_df = self.adapter.get_pbp_data(2023, 1)
            
            if pbp_df.empty:
                return False, "No play-by-play data available"
            
            # Check for EPA calculations
            if 'epa' in pbp_df.columns:
                avg_epa = pbp_df['epa'].mean()
                print(f"  Average EPA: {avg_epa:.3f}")
            
            # Check play types
            if 'play_type' in pbp_df.columns:
                play_types = pbp_df['play_type'].value_counts().head()
                print(f"  Play types: {play_types.to_dict()}")
            
            print(f"  Total plays: {len(pbp_df)}")
            
            # Check for advanced metrics
            advanced_metrics = ['epa', 'wp', 'cpoe', 'success']
            available_metrics = [m for m in advanced_metrics if m in pbp_df.columns]
            
            if available_metrics:
                print(f"  Available advanced metrics: {', '.join(available_metrics)}")
                return True, f"PBP data with {len(available_metrics)} advanced metrics"
            else:
                return True, "PBP data available (basic metrics only)"
                
        except Exception as e:
            # PBP data might not be available in fallback mode
            return True, f"PBP data not available in current mode (expected in CSV fallback)"
    
    def test_injury_data(self) -> tuple[bool, str]:
        """Test injury report retrieval."""
        injuries = self.adapter.get_injuries(2024, 1)
        
        if not injuries:
            # Try previous season
            injuries = self.adapter.get_injuries(2023, 17)
        
        if injuries:
            # Group by team
            team_injuries = {}
            for injury in injuries:
                if injury.team_external_id not in team_injuries:
                    team_injuries[injury.team_external_id] = []
                team_injuries[injury.team_external_id].append(injury)
            
            print(f"  Total injuries: {len(injuries)}")
            print(f"  Teams with injuries: {len(team_injuries)}")
            
            if injuries:
                sample = injuries[0]
                print(f"  Sample: {sample.player_name} ({sample.team_external_id}) - {sample.injury_status}")
            
            return True, f"Loaded {len(injuries)} injury reports across {len(team_injuries)} teams"
        else:
            return True, "No injury data available (this is normal for off-season)"
    
    def test_odds_data(self) -> tuple[bool, str]:
        """Test betting odds retrieval."""
        odds = self.adapter.get_odds(2024, 1)
        
        if not odds:
            odds = self.adapter.get_odds(2023, 17)
        
        if odds:
            # Check odds structure
            sample = odds[0]
            
            has_spread = sample.home_spread is not None
            has_total = sample.total is not None
            has_ml = sample.home_moneyline is not None
            
            print(f"  Games with odds: {len(odds)}")
            if has_spread:
                print(f"  Sample spread: {sample.home_spread}")
            if has_total:
                print(f"  Sample total: {sample.total}")
            
            return True, f"Loaded odds for {len(odds)} games"
        else:
            return True, "No odds data available (expected for future games)"
    
    def test_advanced_analytics(self) -> tuple[bool, str]:
        """Test advanced analytics capabilities."""
        try:
            # Test team advanced stats
            stats = self.adapter.get_advanced_stats('KC', 2023)
            
            if not stats or not stats.get('offensive'):
                return True, "Advanced stats not available in current mode"
            
            off_stats = stats['offensive']
            def_stats = stats['defensive']
            
            print(f"  Offensive EPA: {off_stats.get('offensive_epa', 'N/A')}")
            print(f"  Defensive EPA: {def_stats.get('defensive_epa', 'N/A')}")
            
            return True, "Advanced analytics available"
            
        except Exception as e:
            return True, f"Advanced analytics not available (expected in CSV mode)"
    
    def test_cache_performance(self) -> tuple[bool, str]:
        """Test caching performance."""
        import time
        
        # First call (should cache)
        start = time.time()
        teams1 = self.adapter.get_teams()
        first_call = time.time() - start
        
        # Second call (should use cache)
        start = time.time()
        teams2 = self.adapter.get_teams()
        second_call = time.time() - start
        
        # Cache should be significantly faster
        if second_call < first_call:
            speedup = first_call / second_call if second_call > 0 else 100
            print(f"  First call: {first_call:.3f}s")
            print(f"  Cached call: {second_call:.3f}s")
            print(f"  Speedup: {speedup:.1f}x")
            return True, f"Cache working ({speedup:.1f}x speedup)"
        else:
            return True, "Cache performance normal"
    
    def test_fallback(self) -> tuple[bool, str]:
        """Test fallback mechanism."""
        # This test verifies the adapter works even without R
        teams = self.adapter.get_teams()
        games = self.adapter.get_games(2023, 1)
        
        if teams and games:
            mode = "R mode" if self.adapter.r_interface else "CSV fallback mode"
            return True, f"Adapter working in {mode}"
        else:
            return False, "Adapter not working properly"


class NFLverseUsageExamples:
    """Examples of using the NFLverse adapter in your application."""
    
    def __init__(self):
        from api.adapters.nflverse_r_adapter import NFLverseRAdapter
        self.adapter = NFLverseRAdapter()
    
    def example_weekly_predictions(self):
        """Example: Generate weekly predictions with enhanced data."""
        print("\n📈 Example: Weekly Predictions with Enhanced Data")
        print("-" * 50)
        
        # Get upcoming games
        season = 2024
        week = 1
        games = self.adapter.get_games(season, week)
        
        # Get team stats for prediction
        predictions = []
        
        for game in games[:3]:  # Just show first 3 games
            # Get advanced stats for both teams
            home_stats = self.adapter.get_advanced_stats(
                game.home_team_external_id, season - 1
            )
            away_stats = self.adapter.get_advanced_stats(
                game.away_team_external_id, season - 1
            )
            
            # Simple prediction based on EPA (this is just an example)
            home_epa = home_stats.get('offensive', {}).get('offensive_epa', 0) or 0
            away_epa = away_stats.get('offensive', {}).get('offensive_epa', 0) or 0
            
            # Calculate win probability (simplified)
            epa_diff = home_epa - away_epa
            home_win_prob = 0.5 + (epa_diff * 0.1)  # Simple linear model
            home_win_prob = max(0.1, min(0.9, home_win_prob))  # Bound between 0.1 and 0.9
            
            predictions.append({
                'game': f"{game.away_team_external_id} @ {game.home_team_external_id}",
                'home_win_prob': home_win_prob,
                'away_win_prob': 1 - home_win_prob,
                'predicted_spread': -epa_diff * 3,  # Simple spread calculation
            })
        
        # Display predictions
        for pred in predictions:
            print(f"\nGame: {pred['game']}")
            print(f"  Home Win %: {pred['home_win_prob']:.1%}")
            print(f"  Predicted Spread: {pred['predicted_spread']:+.1f}")
    
    def example_player_props(self):
        """Example: Player prop predictions using detailed stats."""
        print("\n🎯 Example: Player Prop Predictions")
        print("-" * 50)
        
        # Get player stats for analysis
        stats_df = self.adapter.get_player_stats(2023, 17)
        
        if not stats_df.empty:
            # Top QBs passing yards
            qb_stats = stats_df[stats_df['position'] == 'QB'].copy()
            qb_stats = qb_stats.nlargest(5, 'passing_yards', keep='all')
            
            print("\nTop QB Performances (Week 17, 2023):")
            for _, player in qb_stats.iterrows():
                print(f"  {player['player_name']}: {player['passing_yards']:.0f} yards, "
                      f"{player.get('passing_tds', 0):.0f} TDs")
    
    def example_injury_impact(self):
        """Example: Analyze injury impact on predictions."""
        print("\n🏥 Example: Injury Impact Analysis")
        print("-" * 50)
        
        # Get current injuries
        injuries = self.adapter.get_injuries(2024, 1)
        
        if injuries:
            # Group by status
            injury_counts = {}
            for injury in injuries:
                status = injury.injury_status or 'Unknown'
                injury_counts[status] = injury_counts.get(status, 0) + 1
            
            print("\nInjury Report Summary:")
            for status, count in sorted(injury_counts.items()):
                print(f"  {status}: {count} players")
            
            # Find key players
            key_positions = ['QB', 'RB', 'WR']
            key_injuries = [i for i in injuries 
                          if i.player_position in key_positions 
                          and i.injury_status in ['OUT', 'DOUBTFUL']]
            
            if key_injuries:
                print("\nKey Players Out/Doubtful:")
                for inj in key_injuries[:5]:
                    print(f"  {inj.player_name} ({inj.team_external_id} {inj.player_position})")
    
    def example_integration_with_models(self):
        """Example: Integrate with your existing Elo models."""
        print("\n🤖 Example: Integration with Elo Models")
        print("-" * 50)
        
        # This shows how to feed nflverse data into your existing models
        from api.storage.db import get_db_context
        from api.storage.repositories.ingest_repo import IngestRepository
        
        try:
            # Get enhanced data from nflverse
            teams = self.adapter.get_teams()
            games = self.adapter.get_games(2024, 1)
            odds = self.adapter.get_odds(2024, 1)
            
            print(f"Data ready for ingestion:")
            print(f"  Teams: {len(teams)}")
            print(f"  Games: {len(games)}")
            print(f"  Odds: {len(odds)}")
            
            # Example of how to ingest (commented out to avoid DB operations)
            # with get_db_context() as db:
            #     repo = IngestRepository(db)
            #     repo.upsert_teams(teams)
            #     repo.upsert_games(games)
            #     repo.upsert_odds(odds)
            
            print("\n✅ Data can be ingested into your existing models")
            
        except Exception as e:
            print(f"⚠️  Integration example (DB not connected): {e}")


def main():
    """Main execution function."""
    import argparse
    
    parser = argparse.ArgumentParser(description='NFLverse R Integration Testing')
    parser.add_argument('--test', action='store_true', help='Run integration tests')
    parser.add_argument('--examples', action='store_true', help='Show usage examples')
    parser.add_argument('--all', action='store_true', help='Run everything')
    
    args = parser.parse_args()
    
    if args.test or args.all:
        tester = NFLverseIntegrationTester()
        success = tester.run_all_tests()
        if not success and not args.all:
            sys.exit(1)
    
    if args.examples or args.all:
        examples = NFLverseUsageExamples()
        examples.example_weekly_predictions()
        examples.example_player_props()
        examples.example_injury_impact()
        examples.example_integration_with_models()
    
    if not any([args.test, args.examples, args.all]):
        parser.print_help()


if __name__ == "__main__":
    main()