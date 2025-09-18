# Patch for nflverse_adapter.py
import pandas as pd

# Update the get_games method to handle NaN values before creating GameDTO
def safe_string(value):
    """Convert value to string, handling NaN."""
    if pd.isna(value):
        return None
    return str(value) if value else None

def safe_float(value):
    """Convert value to float, handling NaN."""
    if pd.isna(value):
        return None
    try:
        return float(value)
    except:
        return None
