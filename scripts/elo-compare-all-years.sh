#!/bin/bash
# elo-compare-all-years.sh - Compare model performance for ALL possible year ranges

echo "🔬 COMPREHENSIVE ELO MODEL COMPARISON"
echo "======================================"
echo ""
echo "Testing ALL training configurations from each year to 2025..."
echo "This will take a few minutes..."
echo ""

docker exec nflpred-api python -c "
import sys
sys.path.append('/app')
from api.models.elo_model import EloModel
from api.storage.db import get_db_context
import numpy as np

# Generate configs for every starting year
configs = []
for start_year in range(2015, 2025):  # 2015 to 2024 as starting points
    years_included = 2025 - start_year + 1
    configs.append({
        'name': f'{start_year}-2025 ({years_included} years)',
        'start': start_year,
        'end': 2025
    })

# Store results for summary
all_results = []

for i, config in enumerate(configs, 1):
    print(f\"Testing {i}/{len(configs)}: {config['name']}...\")
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
        'start': config['start'],
        'total_games': total_games,
        'overall_acc': overall_acc,
        'acc_2023': acc_2023,
        'acc_2024': acc_2024,
        'acc_2025': acc_2025,
        'games_2025': games_2025
    })

# Clear line for results
print('')
print('='*105)
print('COMPLETE RESULTS - ALL YEAR RANGES')
print('='*105)
print('')
print('Training Range        | Total Games | Overall | 2023 Acc | 2024 Acc | 2025 Acc (current)')
print('----------------------|-------------|---------|----------|----------|-------------------')

# Find best for each metric
best_overall = max(all_results, key=lambda x: x['overall_acc'])['overall_acc']
best_2023 = max(all_results, key=lambda x: x['acc_2023'])['acc_2023']
best_2024 = max(all_results, key=lambda x: x['acc_2024'])['acc_2024']
best_2025 = max(all_results, key=lambda x: x['acc_2025'])['acc_2025']

for result in all_results:
    # Add indicators for best in each category
    mark_overall = '✓' if abs(result['overall_acc'] - best_overall) < 0.1 else ' '
    mark_2023 = '✓' if abs(result['acc_2023'] - best_2023) < 0.1 else ' '
    mark_2024 = '✓' if abs(result['acc_2024'] - best_2024) < 0.1 else ' '
    mark_2025 = '✓' if abs(result['acc_2025'] - best_2025) < 0.1 else ' '
    
    print(f\"{result['name']:21} | {result['total_games']:11} | {result['overall_acc']:5.1f}% {mark_overall} | {result['acc_2023']:5.1f}% {mark_2023} | {result['acc_2024']:5.1f}% {mark_2024} | {result['acc_2025']:5.1f}% {mark_2025} ({result['games_2025']} games)\")

print('')
print('='*105)
print('✓ = Best (or within 0.1% of best) accuracy for that metric')
print(f\"📊 2025 Status: {result['games_2025']} games completed (Weeks 1-2)\")
print('')

# Analysis section
print('📈 KEY INSIGHTS:')
print('-' * 50)

# Find optimal for 2025
best_2025_config = max(all_results, key=lambda x: x['acc_2025'])
print(f\"Best for 2025: {best_2025_config['name']} with {best_2025_config['acc_2025']:.1f}% accuracy\")

# Find optimal overall
best_overall_config = max(all_results, key=lambda x: x['overall_acc'])
print(f\"Best overall:  {best_overall_config['name']} with {best_overall_config['overall_acc']:.1f}% accuracy\")

# Find sweet spot (good at both)
for result in all_results:
    result['combined_score'] = (result['acc_2025'] * 2 + result['acc_2024'] + result['acc_2023']) / 4

best_combined = max(all_results, key=lambda x: x['combined_score'])
print(f\"Best recent years (2023-2025): {best_combined['name']}\")

# Trend analysis
print('')
print('📉 TREND ANALYSIS:')
print('-' * 50)
print('Starting Year | 2025 Accuracy | Total Games | Observation')
print('--------------|---------------|-------------|------------')

# Group by performance tiers
for result in sorted(all_results, key=lambda x: x['start']):
    if result['acc_2025'] >= 75:
        tier = '🟢 Excellent'
    elif result['acc_2025'] >= 70:
        tier = '🟡 Good'
    elif result['acc_2025'] >= 65:
        tier = '🟠 Fair'
    else:
        tier = '🔴 Poor'
    
    print(f\"{result['start']}          | {result['acc_2025']:13.1f}% | {result['total_games']:11} | {tier}\")

print('')
print('='*105)

# Final recommendation
recent_scores = [(r['name'], r['acc_2025']) for r in all_results if r['start'] >= 2018]
recent_scores.sort(key=lambda x: x[1], reverse=True)

print('⭐ RECOMMENDATIONS:')
print(f\"   1. For 2025 predictions: Use {best_2025_config['name']}\")
print(f\"   2. For overall accuracy: Use {best_overall_config['name']}\")
print(f\"   3. For balanced recent performance: Use {best_combined['name']}\")
print('='*105)
"