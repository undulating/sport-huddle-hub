#!/usr/bin/env python3
"""Test provider adapters."""
import sys
sys.path.append('.')

from api.adapters.base import ProviderRegistry
from api.adapters.mock_adapter import MockAdapter

def test_providers():
    print("Testing Provider Adapters...")
    
    # Test registry
    providers = ProviderRegistry.list_providers()
    print(f"✅ Available providers: {providers}")
    
    # Get mock adapter
    adapter = ProviderRegistry.get_adapter("mock")
    print(f"✅ Got adapter: {adapter.provider_name}")
    
    # Test getting teams
    teams = adapter.get_teams()
    print(f"✅ Loaded {len(teams)} teams")
    print(f"   Sample team: {teams[0].name} ({teams[0].abbreviation})")
    
    # Test getting games
    games = adapter.get_games(2024, 1)
    print(f"✅ Loaded {len(games)} games for Week 1")
    if games:
        print(f"   Sample game: {games[0].home_team_external_id} vs {games[0].away_team_external_id}")
    
    # Test getting odds
    odds = adapter.get_odds(2024, 1)
    print(f"✅ Loaded {len(odds)} odds records")
    if odds:
        print(f"   Sample spread: {odds[0].home_spread}")
    
    # Test getting injuries
    injuries = adapter.get_injuries(2024, 1)
    print(f"✅ Loaded {len(injuries)} injury reports")
    
    print("\n✅ Phase 3 Provider Setup Complete!")

if __name__ == "__main__":
    test_providers()
