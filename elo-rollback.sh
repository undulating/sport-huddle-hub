#!/bin/bash
# elo-rollback.sh - Rollback to a previous backup

echo "⏪ ELO ROLLBACK UTILITY"
echo "======================="
echo ""

BACKUP_DIR="./elo_backups"

# List available backups
echo "Available backups:"
ls -la $BACKUP_DIR/*.json 2>/dev/null | tail -5

echo ""
echo "To rollback, run:"
echo "  docker exec nflpred-api python /app/api/scripts/elo_utilities.py rollback --backup /path/to/backup.json"
echo ""
echo "Example:"
LATEST_BACKUP=$(ls -t $BACKUP_DIR/*.json 2>/dev/null | head -1)
if [ ! -z "$LATEST_BACKUP" ]; then
    echo "  docker cp $LATEST_BACKUP nflpred-api:/tmp/backup.json"
    echo "  docker exec nflpred-api python -c \"
import sys
sys.path.append('/app')
from api.scripts.elo_utilities import EloManager
manager = EloManager()
manager.rollback_to_backup('/tmp/backup.json')
\""
fi