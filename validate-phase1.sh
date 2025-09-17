#!/bin/bash
# validate-phase1.sh
# Validates that Phase 1 is complete and working

set -e

echo "==================================="
echo "Phase 1 Validation"
echo "==================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Validation results
PASSED=0
FAILED=0

validate() {
    local test_name=$1
    local command=$2
    
    echo -n "Checking $test_name... "
    
    if eval $command > /dev/null 2>&1; then
        echo -e "${GREEN}✅ PASSED${NC}"
        ((PASSED++))
        return 0
    else
        echo -e "${RED}❌ FAILED${NC}"
        ((FAILED++))
        return 1
    fi
}

# Check directory structure
validate "Directory structure" "test -d api && test -d ops && test -d api/routes && test -d api/storage"

# Check required files
validate "README.md exists" "test -f README.md"
validate ".gitignore exists" "test -f .gitignore"
validate "pyproject.toml exists" "test -f pyproject.toml"
validate "Docker Compose file" "test -f ops/docker-compose.yml"
validate "API Dockerfile" "test -f ops/api.Dockerfile"
validate "Main app file" "test -f api/app.py"
validate "Config file" "test -f api/config.py"
validate "Health route" "test -f api/routes/health.py"

# Check environment file
if [ ! -f .env ]; then
    echo -e "${YELLOW}⚠️  .env file not found, creating from template...${NC}"
    cp .env.example .env
fi
validate "Environment file" "test -f .env"

# Check Python dependencies
echo -n "Checking Poetry... "
if command -v poetry &> /dev/null; then
    echo -e "${GREEN}✅ Installed${NC}"
    ((PASSED++))
    
    # Install dependencies if not already installed
    if [ ! -d ".venv" ] && [ ! -f "poetry.lock" ]; then
        echo "Installing Python dependencies..."
        poetry install
    fi
else
    echo -e "${YELLOW}⚠️  Poetry not installed${NC}"
    echo "Install with: curl -sSL https://install.python-poetry.org | python3 -"
    ((FAILED++))
fi

# Check Docker
validate "Docker installed" "command -v docker"
validate "Docker Compose installed" "command -v docker || command -v docker-compose"

# Check if services are running
echo ""
echo "Checking Docker services..."
cd ops

# Start services if not running
if ! docker compose ps | grep -q "nflpred-db.*running"; then
    echo "Starting database..."
    docker compose up -d db
    sleep 5
fi

if ! docker compose ps | grep -q "nflpred-redis.*running"; then
    echo "Starting Redis..."
    docker compose up -d redis
    sleep 3
fi

validate "PostgreSQL running" "docker compose ps | grep -q 'nflpred-db.*running'"
validate "Redis running" "docker compose ps | grep -q 'nflpred-redis.*running'"

# Test database connection
validate "PostgreSQL accessible" "docker compose exec -T db psql -U nflpred -d nflpred -c 'SELECT 1'"

# Test Redis connection
validate "Redis accessible" "docker compose exec -T redis redis-cli ping | grep -q PONG"

# Test API if running
echo ""
echo "Checking API..."
if docker compose ps | grep -q "nflpred-api.*running"; then
    sleep 2
    validate "API health endpoint" "curl -s http://localhost:8000/api/ping | grep -q 'ok'"
    validate "API docs accessible" "curl -s http://localhost:8000/docs | grep -q 'swagger-ui'"
else
    echo -e "${YELLOW}⚠️  API not running. Start with: cd ops && docker compose up api${NC}"
fi

# Summary
echo ""
echo "==================================="
echo "Validation Summary"
echo "==================================="
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"

if [ $FAILED -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ Phase 1 Complete!${NC}"
    echo ""
    echo "All infrastructure is ready. You can now:"
    echo "1. Start the API: cd ops && docker compose up api"
    echo "2. View API docs: http://localhost:8000/docs"
    echo "3. Test endpoint: curl http://localhost:8000/api/ping"
    echo ""
    echo "Ready to proceed to Phase 2: Database Schema & Models"
else
    echo ""
    echo -e "${RED}❌ Phase 1 Incomplete${NC}"
    echo ""
    echo "Please fix the failed checks before proceeding."
    echo "Run this script again to re-validate."
fi

exit $FAILED