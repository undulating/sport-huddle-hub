"""
NFLverse R Integration Configuration
"""

import os
from pathlib import Path

# NFLverse adapter configuration
NFLVERSE_CONFIG = {
    # Use local R installation
    "use_r": os.getenv("USE_NFLVERSE_R", "true").lower() == "true",
    
    # Cache settings
    "cache_enabled": True,
    "cache_dir": os.getenv("NFLVERSE_CACHE_DIR", "/tmp/nflverse_cache"),
    "cache_ttl": int(os.getenv("NFLVERSE_CACHE_TTL", "3600")),  # 1 hour default
    
    # Data settings
    "default_seasons": [2020, 2021, 2022, 2023, 2024],
    "auto_update": True,  # Auto-update data on startup
    
    # Performance settings
    "parallel_processing": True,
    "max_workers": 4,
    
    # Fallback settings
    "fallback_to_csv": True,  # Fall back to CSV if R fails
    
    # Advanced statistics to calculate
    "calculate_advanced_stats": [
        "epa",  # Expected Points Added
        "cpoe",  # Completion Percentage Over Expected
        "success_rate",  # Success rate by down
        "explosive_plays",  # 20+ yard plays
        "pressure_rate",  # QB pressure rate
        "yards_after_contact",  # RB YAC
        "separation",  # WR separation
        "win_probability",  # Win probability added
    ]
}

# R environment configuration
R_CONFIG = {
    "r_home": os.getenv("R_HOME", None),  # Auto-detect if not set
    "r_libs_user": os.getenv("R_LIBS_USER", None),
    "max_memory": "4G",  # Maximum memory for R processes
}
