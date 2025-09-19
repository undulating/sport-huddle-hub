#!/bin/bash
# debug-script.sh - Figure out why elo-recent-retrain.sh won't run

echo "🔍 DEBUGGING SCRIPT EXECUTION"
echo "============================="
echo ""

# 1. Check if file exists and permissions
echo "1. Checking file status..."
if [ -f "./elo-recent-retrain.sh" ]; then
    echo "   ✅ File exists"
    ls -la ./elo-recent-retrain.sh
else
    echo "   ❌ File not found in current directory"
    echo "   Current directory: $(pwd)"
    echo "   Files matching 'elo':"
    ls -la | grep elo
fi

# 2. Check file format (DOS vs Unix line endings)
echo ""
echo "2. Checking file format..."
if [ -f "./elo-recent-retrain.sh" ]; then
    # Check for DOS line endings
    if file ./elo-recent-retrain.sh | grep -q "CRLF"; then
        echo "   ⚠️ File has Windows (CRLF) line endings - this prevents execution!"
        echo "   Fix with: dos2unix elo-recent-retrain.sh"
        echo "   Or: sed -i 's/\r$//' elo-recent-retrain.sh"
    else
        echo "   ✅ File has Unix line endings"
    fi
    
    # Check first line
    echo "   First line of script:"
    head -n 1 ./elo-recent-retrain.sh | cat -A
    echo "   (Should show: #!/bin/bash$)"
fi

# 3. Try to execute with explicit bash
echo ""
echo "3. Testing execution methods..."

# Method 1: Direct execution
echo "   Method 1 - Direct (./):"
./elo-recent-retrain.sh 2>&1 | head -5 || echo "   Failed with exit code: $?"

# Method 2: Explicit bash
echo ""
echo "   Method 2 - Explicit bash:"
bash elo-recent-retrain.sh 2>&1 | head -5 || echo "   Failed with exit code: $?"

# Method 3: Source
echo ""
echo "   Method 3 - Debug first few lines:"
bash -x elo-recent-retrain.sh 2>&1 | head -10 || echo "   Failed with exit code: $?"

# 4. Check if Docker is running
echo ""
echo "4. Checking Docker status..."
if docker ps >/dev/null 2>&1; then
    echo "   ✅ Docker is running"
    
    # Check if container exists
    if docker ps | grep -q "nflpred-api"; then
        echo "   ✅ nflpred-api container is running"
    else
        echo "   ❌ nflpred-api container is not running"
        echo "   Start with: docker compose up -d api"
    fi
else
    echo "   ❌ Docker is not accessible"
fi

# 5. Test a simple Docker command
echo ""
echo "5. Testing Docker exec..."
docker exec nflpred-api echo "Docker exec works" 2>&1 || echo "   ❌ Docker exec failed"

echo ""
echo "============================="
echo "DIAGNOSIS COMPLETE"
echo ""
echo "Common fixes:"
echo "1. Line endings: dos2unix elo-recent-retrain.sh"
echo "2. Or on Mac: sed -i '' 's/\r$//' elo-recent-retrain.sh"
echo "3. Or recreate: cat elo-recent-retrain.sh | tr -d '\r' > temp.sh && mv temp.sh elo-recent-retrain.sh"
echo "4. Make executable: chmod +x elo-recent-retrain.sh"
echo "5. Run with bash: bash elo-recent-retrain.sh"