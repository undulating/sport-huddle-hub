import pathlib

APP_PY = pathlib.Path(__file__).with_name("app.py")
text = APP_PY.read_text()

# 1) add import for the new router
text = text.replace(
    "from api.routes import health",
    "from api.routes import health, ingest"
)

# 2) include the new router
text = text.replace(
    "app.include_router(health.router, prefix='/api', tags=['health'])",
    "app.include_router(health.router, prefix='/api', tags=['health'])\n"
    "app.include_router(ingest.router, prefix='/api/ingest', tags=['ingest'])"
)

APP_PY.write_text(text)
print("✅ updated", APP_PY)
