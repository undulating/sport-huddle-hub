#!/usr/bin/env python3
"""
Migration script to switch from CSV-based NFLverse to R-based NFLverse
"""

import sys
sys.path.insert(0, '.')

from api.adapters.base import ProviderRegistry
from api.config import settings
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def migrate_to_nflverse_r():
    """Migrate from CSV adapter to R adapter."""
    
    logger.info("Starting migration to NFLverse R adapter...")
    
    # Update provider in settings
    if hasattr(settings, 'PROVIDER'):
        old_provider = settings.PROVIDER
        settings.PROVIDER = 'nflverse_r'
        logger.info(f"Changed provider from '{old_provider}' to 'nflverse_r'")
    
    # Test the new adapter
    try:
        from api.adapters.nflverse_r_adapter import NFLverseRAdapter
        adapter = ProviderRegistry.get_adapter('nflverse_r')
        
        # Test basic functionality
        teams = adapter.get_teams()
        logger.info(f"✅ New adapter working: fetched {len(teams)} teams")
        
        # Clear old cache if exists
        import shutil
        import os
        old_cache = "/tmp/nflverse_cache_old"
        if os.path.exists("/tmp/nflverse_cache"):
            shutil.move("/tmp/nflverse_cache", old_cache)
            logger.info(f"Moved old cache to {old_cache}")
        
        logger.info("✅ Migration complete!")
        return True
        
    except Exception as e:
        logger.error(f"Migration failed: {e}")
        return False


if __name__ == "__main__":
    success = migrate_to_nflverse_r()
    sys.exit(0 if success else 1)
