import sys
sys.path.append('/app')

# Read current app.py
with open('/app/api/app.py', 'r') as f:
    content = f.read()

# Add import for ingest router
import_line = "from api.routes import health, ingest"
content = content.replace("from api.routes import health", import_line)

# Add router inclusion
router_line = 'app.include_router(health.router, prefix="/api", tags=["health"])\napp.include_router(ingest.router, prefix="/api/ingest", tags=["ingest"])'
content = content.replace('app.include_router(health.router, prefix="/api", tags=["health"])', router_line)

# Write back
with open('/app/api/app.py', 'w') as f:
    f.write(content)

print("✅ App.py updated with ingest routes")
