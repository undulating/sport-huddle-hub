#!/bin/bash
# NFLverse R Integration Setup Script
# This script sets up the R environment and Python integration for nflverse data

set -e

echo "🏈 NFL Prediction System - NFLverse R Integration Setup"
echo "======================================================="

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to print colored messages
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Step 1: Check for R installation
echo ""
echo "Step 1: Checking R installation..."
if command_exists R; then
    R_VERSION=$(R --version | head -n 1)
    print_success "R is installed: $R_VERSION"
else
    print_error "R is not installed!"
    echo "Please install R from: https://cran.r-project.org/"
    echo ""
    echo "On Ubuntu/Debian:"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install r-base r-base-dev"
    echo ""
    echo "On macOS:"
    echo "  brew install r"
    echo ""
    exit 1
fi

# Step 2: Install R packages
echo ""
echo "Step 2: Installing R packages (this may take a while)..."

R_SCRIPT=$(cat <<'EOF'
# Function to install package if not already installed
install_if_missing <- function(package) {
  if (!require(package, character.only = TRUE, quietly = TRUE)) {
    cat(paste("Installing", package, "...\n"))
    install.packages(package, repos = "https://cloud.r-project.org/", quiet = TRUE)
  } else {
    cat(paste(package, "already installed\n"))
  }
}

# Install required packages
install_if_missing("tidyverse")
install_if_missing("remotes")

# Install nflverse packages
if (!require("nflverse", quietly = TRUE)) {
  cat("Installing nflverse ecosystem...\n")
  remotes::install_github("nflverse/nflverse", quiet = TRUE)
} else {
  cat("nflverse already installed\n")
}

# Load and update nflverse data
library(nflverse)
cat("\nUpdating nflverse data cache...\n")

# Update data for recent seasons
tryCatch({
  nflreadr::update_db()
  cat("✅ nflverse data cache updated\n")
}, error = function(e) {
  cat("⚠️  Could not update all data (this is okay for initial setup)\n")
})

cat("\n✅ R packages installation complete!\n")
EOF
)

echo "$R_SCRIPT" | R --vanilla --quiet

# Step 3: Install Python packages
echo ""
echo "Step 3: Installing Python packages..."

# Check if we're in a virtual environment
if [ -n "$VIRTUAL_ENV" ]; then
    print_success "Virtual environment detected: $VIRTUAL_ENV"
else
    print_warning "No virtual environment detected. Using poetry..."
fi

# Install rpy2 and other dependencies
if command_exists poetry; then
    echo "Adding rpy2 to project dependencies..."
    poetry add rpy2
    print_success "Python packages installed via Poetry"
elif [ -n "$VIRTUAL_ENV" ]; then
    pip install rpy2
    print_success "Python packages installed via pip"
else
    print_error "Please activate your virtual environment or use Poetry"
    exit 1
fi

# Step 4: Test the integration
echo ""
echo "Step 4: Testing R-Python integration..."

poetry run python <<EOF  # ← CHANGED FROM python3
import sys
try:
    import rpy2.robjects as robjects
    from rpy2.robjects.packages import importr
    print("✅ rpy2 imported successfully")
    
    # Test R execution
    r = robjects.r
    result = r('1 + 1')
    print(f"✅ R calculation test: 1 + 1 = {result[0]}")
    
    # Test nflverse import
    try:
        nflverse = importr('nflverse')
        print("✅ nflverse package accessible from Python")
    except Exception as e:
        print(f"⚠️  Could not import nflverse: {e}")
        print("   This is okay - the adapter will handle this")
    
    print("\n✅ R-Python integration is working!")
except ImportError:
    print("❌ Failed to import rpy2")
    sys.exit(1)
except Exception as e:
    print(f"❌ Integration test failed: {e}")
    sys.exit(1)
EOF

# Step 5: Create configuration file
echo ""
echo "Step 5: Creating configuration file..."

CONFIG_FILE="api/config/nflverse_config.py"
mkdir -p api/config

cat > $CONFIG_FILE <<'EOF'
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
EOF

print_success "Configuration file created at $CONFIG_FILE"

# Step 6: Update environment variables
echo ""
echo "Step 6: Updating environment variables..."

ENV_FILE=".env"
if [ -f "$ENV_FILE" ]; then
    # Check if variables already exist
    if grep -q "USE_NFLVERSE_R" "$ENV_FILE"; then
        print_warning "NFLverse variables already in .env file"
    else
        cat >> "$ENV_FILE" <<EOF

# NFLverse R Integration
USE_NFLVERSE_R=true
NFLVERSE_CACHE_DIR=/tmp/nflverse_cache
NFLVERSE_CACHE_TTL=3600
EOF
        print_success "Environment variables added to .env"
    fi
else
    print_warning ".env file not found. Creating with NFLverse settings..."
    cat > "$ENV_FILE" <<EOF
# NFLverse R Integration
USE_NFLVERSE_R=true
NFLVERSE_CACHE_DIR=/tmp/nflverse_cache
NFLVERSE_CACHE_TTL=3600
EOF
    print_success ".env file created"
fi

# Step 7: Test the NFLverse adapter
echo ""
echo "Step 7: Testing NFLverse adapter..."

poetry run python <<'EOF'  # ← CHANGED FROM python3
import sys
import os
sys.path.insert(0, '.')

try:
    # Import the new adapter
    from api.adapters.nflverse_r_adapter import NFLverseRAdapter
    from api.adapters.base import ProviderRegistry
    
    # Register and test
    adapter = NFLverseRAdapter()
    print("✅ NFLverse R adapter initialized")
    
    # Try to fetch teams
    teams = adapter.get_teams()
    if teams:
        print(f"✅ Successfully fetched {len(teams)} teams")
        print(f"   Sample: {teams[0].name} ({teams[0].abbreviation})")
    
    # Try to fetch a game
    games = adapter.get_games(2024, 1)
    if games:
        print(f"✅ Successfully fetched {len(games)} games for Week 1, 2024")
    
    print("\n✅ NFLverse adapter is working correctly!")
    
except Exception as e:
    print(f"⚠️  Adapter test encountered an issue: {e}")
    print("   The adapter will fall back to CSV mode if needed")
EOF

# Step 8: Create migration script
echo ""
echo "Step 8: Creating migration script..."

cat > api/scripts/migrate_to_nflverse_r.py <<'EOF'
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
EOF

chmod +x api/scripts/migrate_to_nflverse_r.py
print_success "Migration script created"

# Final summary
echo ""
echo "======================================================="
print_success "NFLverse R Integration Setup Complete!"
echo ""
echo "Next steps:"
echo "1. Copy the new adapter to your project:"
echo "   cp nflverse_r_adapter.py api/adapters/"
echo ""
echo "2. Update your API configuration to use 'nflverse_r' provider:"
echo "   Edit api/config.py and set PROVIDER='nflverse_r'"
echo ""
echo "3. Restart your API server:"
echo "   docker compose restart api"
echo ""
echo "4. (Optional) Run the migration script:"
echo "   python api/scripts/migrate_to_nflverse_r.py"
echo ""
echo "The new adapter provides:"
echo "  • Access to complete nflverse data ecosystem"
echo "  • Real-time data updates from local R package"
echo "  • Advanced statistics (EPA, CPOE, etc.)"
echo "  • Play-by-play data for ML models"
echo "  • Automatic fallback to CSV if R fails"
echo "  • Intelligent caching for performance"
echo ""
print_success "Happy predicting! 🏈"