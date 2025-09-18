#!/bin/bash
# quick-test.sh - Quick test to verify API is working

echo "==================================="
echo "Quick API Test"
echo "==================================="

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 1. Check containers
echo ""
echo "1. Docker Containers Status:"
cd ops 2>/dev/null
docker compose ps --format "table {{.Name}}\t{{.Status}}"

# 2. Test database directly with simpler command
echo ""
echo "2. Testing PostgreSQL:"
docker exec nflpred-db pg_isready -U nflpred && echo -e "${GREEN}✅ PostgreSQL is ready${NC}" || echo -e "${YELLOW}⚠️  PostgreSQL may still be initializing${NC}"

# 3. Test Redis
echo ""
echo "3. Testing Redis:"
docker exec nflpred-redis redis-cli ping && echo -e "${GREEN}✅ Redis is ready${NC}" || echo -e "${RED}❌ Redis not responding${NC}"

# 4. Start API if not running
echo ""
echo "4. Checking API:"
if ! docker compose ps | grep -q "nflpred-api.*Up\|nflpred-api.*running"; then
    echo -e "${YELLOW}API not running. Starting it now...${NC}"
    docker compose up -d api
    echo "Waiting for API to start..."
    sleep 5
fi

# 5. Test API endpoint
echo ""
echo "5. Testing API Health Endpoint:"
echo "   Attempting to connect to http://localhost:8000/api/ping"
echo ""

response=$(curl -s http://localhost:8000/api/ping 2>/dev/null)

if [ ! -z "$response" ]; then
    echo -e "${GREEN}✅ API Response:${NC}"
    echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
    echo ""
    echo -e "${GREEN}✨ Phase 1 is COMPLETE!${NC}"
    echo ""
    echo "You can now:"
    echo "  • View API docs at: http://localhost:8000/docs"
    echo "  • View ReDoc at: http://localhost:8000/redoc"
    echo "  • Check logs: docker compose logs -f api"
else
    echo -e "${RED}❌ No response from API${NC}"
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Check if API container is running:"
    echo "   docker compose ps"
    echo ""
    echo "2. Check API logs for errors:"
    echo "   docker compose logs api --tail=50"
    echo ""
    echo "3. Try starting API manually:"
    echo "   docker compose up api"
fi

echo ""
echo "==================================="