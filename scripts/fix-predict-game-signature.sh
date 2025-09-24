#!/bin/bash
# fix-predict-game-signature.sh

echo "====================================="
echo "🔧 FIXING PREDICT_GAME SIGNATURE"
echo "====================================="
echo ""

# Option 1: Quick fix - Update predictions.py to not pass game_date
echo "Applying quick fix to predictions.py..."
cat << 'EOF' > /tmp/predictions_fix.py
# Apply this fix to predictions.py around line 68
# Change FROM:
pred = prediction_model.predict_game(
    game.home_team_id, 
    game.away_team_id,
    game.game_date  # REMOVE THIS LINE
)

# Change TO:
pred = prediction_model.predict_game(
    game.home_team_id, 
    game.away_team_id
)
EOF

# Option 2: Update both models to accept game_date (for future use)
echo ""
echo "Creating updated EloModel with optional game_date parameter..."
cat << 'EOF' > /tmp/elo_model_fix.py
# In api/models/elo_model.py, update the predict_game method signature:

def predict_game(
    self, 
    home_team_id: int, 
    away_team_id: int,
    game_date: Optional[datetime] = None  # Add this parameter
) -> Dict[str, float]:
    """
    Predict outcome of a game.
    
    Args:
        home_team_id: Home team database ID
        away_team_id: Away team database ID
        game_date: Game date (optional, for future enhancements)
    
    Returns:
        Dict with probabilities and predicted scores
    """
    # Rest of the method stays the same
    home_rating = self.ratings.get(home_team_id, self.mean_rating)
    away_rating = self.ratings.get(away_team_id, self.mean_rating)
    # ... rest unchanged
EOF

echo ""
echo "Creating updated EloRecentFormModel with game_date parameter..."
cat << 'EOF' > /tmp/elo_recent_fix.py
# In api/models/elo_recent_form.py, update the predict_game method:

def predict_game(
    self,
    home_team_id: int,
    away_team_id: int,
    game_date: Optional[datetime] = None  # Add this parameter
) -> Dict[str, float]:
    """
    Predict with recent form adjustments.
    
    Args:
        home_team_id: Home team database ID
        away_team_id: Away team database ID
        game_date: Game date (used to find recent games before this date)
    """
    # Get base prediction from parent
    base_prediction = super().predict_game(home_team_id, away_team_id, game_date)
    
    # Get recent form adjustments
    home_form = self.get_team_recent_form(home_team_id, before_date=game_date)
    away_form = self.get_team_recent_form(away_team_id, before_date=game_date)
    # ... rest of the method
EOF

echo ""
echo "====================================="
echo "📋 QUICK FIX INSTRUCTIONS"
echo "====================================="
echo ""
echo "IMMEDIATE FIX (simplest):"
echo "1. Edit api/routes/predictions.py"
echo "2. Find line ~68 where predict_game is called"
echo "3. Remove the 'game.game_date' parameter"
echo ""
echo "From:"
echo "  pred = prediction_model.predict_game("
echo "      game.home_team_id,"
echo "      game.away_team_id,"
echo "      game.game_date  # <- REMOVE THIS"
echo "  )"
echo ""
echo "To:"
echo "  pred = prediction_model.predict_game("
echo "      game.home_team_id,"
echo "      game.away_team_id"
echo "  )"
echo ""
echo "Then restart API:"
echo "  docker compose restart api"
echo ""
echo "====================================="
echo "📋 PROPER FIX (better long-term):"
echo "====================================="
echo ""
echo "Update BOTH model files to accept optional game_date:"
echo ""
echo "1. In api/models/elo_model.py:"
echo "   - Add 'game_date: Optional[datetime] = None' to predict_game()"
echo ""
echo "2. In api/models/elo_recent_form.py:"
echo "   - Add 'game_date: Optional[datetime] = None' to predict_game()"
echo "   - Use it for get_team_recent_form(before_date=game_date)"
echo ""
echo "This way the models can use the date in the future for:"
echo "- Time-weighted predictions"
echo "- Season-specific adjustments"
echo "- Recent form calculations"
echo ""
echo "Choose whichever approach fits your timeline!"