#!/bin/bash
# elo-compare-performance.sh - Compare model performance across different training sets

echo "🔬 ELO MODEL COMPARISON"
echo "======================="
echo ""
echo "Testing different training configurations..."
echo "This may take a minute..."
echo ""

docker exec nflpred-api python -c "
import sys
sys.path.append('/app')
from api.models.elo_model import EloModel
from api.storage.db import get_db_context
import numpy as np

configs = [
    {'name': 'Recent (2020-2025)', 'start': 2020, 'end': 2025},
    {'name': 'Full (2015-2025)', 'start': 2015, 'end': 2025},
    {'name': 'Modern (2018-2025)', 'start': 2018, 'end': 2025},
]

# Store results for summary
all_results = []

for config in configs:
    print(f\"Testing {config['name']}...\")
    elo = EloModel()
    elo.train_on_historical_data(config['start'], config['end'])
    
    # Overall accuracy
    accuracies = []
    total_games = 0
    for season in range(config['start'], config['end'] + 1):
        results = elo.evaluate_predictions(season)
        if results['games'] > 0:
            accuracies.append(results['accuracy'])
            total_games += results['games']
    
    # Recent seasons specific accuracy
    results_2023 = elo.evaluate_predictions(2023)
    results_2024 = elo.evaluate_predictions(2024)
    results_2025 = elo.evaluate_predictions(2025)
    
    overall_acc = np.mean(accuracies) * 100 if accuracies else 0
    acc_2023 = results_2023['accuracy'] * 100 if results_2023['games'] > 0 else 0
    acc_2024 = results_2024['accuracy'] * 100 if results_2024['games'] > 0 else 0
    acc_2025 = results_2025['accuracy'] * 100 if results_2025['games'] > 0 else 0
    games_2025 = results_2025['games']
    
    # Store for final display
    all_results.append({
        'name': config['name'],
        'total_games': total_games,
        'overall_acc': overall_acc,
        'acc_2023': acc_2023,
        'acc_2024': acc_2024,
        'acc_2025': acc_2025,
        'games_2025': games_2025
    })

# Clear line for results
print('')
print('='*95)
print('RESULTS - MODEL COMPARISON')
print('='*95)
print('')
print('Configuration         | Total Games | Overall | 2023 Acc | 2024 Acc | 2025 Acc (current)')
print('----------------------|-------------|---------|----------|----------|-------------------')

# Find best for each year
best_2023 = max(all_results, key=lambda x: x['acc_2023'])['acc_2023']
best_2024 = max(all_results, key=lambda x: x['acc_2024'])['acc_2024']
best_2025 = max(all_results, key=lambda x: x['acc_2025'])['acc_2025']

for result in all_results:
    # Add indicators for best in each year
    mark_2023 = '✓' if result['acc_2023'] == best_2023 else ' '
    mark_2024 = '✓' if result['acc_2024'] == best_2024 else ' '
    mark_2025 = '✓' if result['acc_2025'] == best_2025 else ' '
    
    print(f\"{result['name']:21} | {result['total_games']:11} | {result['overall_acc']:5.1f}%  | {result['acc_2023']:5.1f}% {mark_2023} | {result['acc_2024']:5.1f}% {mark_2024} | {result['acc_2025']:5.1f}% {mark_2025} ({result['games_2025']} games)\")

print('')
print('='*95)
print('✓ = Best accuracy for that year')
print(f\"📊 2025 Status: {result['games_2025']} games completed (Weeks 1-2)\")

# Determine overall recommendation
recent_best_count = {}
for result in all_results:
    count = 0
    if result['acc_2023'] == best_2023: count += 1
    if result['acc_2024'] == best_2024: count += 1
    if result['acc_2025'] == best_2025: count += 1
    recent_best_count[result['name']] = count

best_config = max(recent_best_count, key=recent_best_count.get)
print(f\"⭐ RECOMMENDATION: {best_config} - Best for recent seasons\")
print('='*95)
"