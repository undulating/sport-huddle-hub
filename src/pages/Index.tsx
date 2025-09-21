// src/pages/Index.tsx
// Updated with working model selector that changes predictions

import { useState, useEffect } from 'react';
import { SportType, Game } from '@/types/sports';
import { mockSeason, mockGames } from '@/data/mockData';
import { DashboardHeader } from '@/components/DashboardHeader';
import { GameCard } from '@/components/GameCard';
import { ModelSelector } from '@/components/ModelSelector';
import {
  fetchWeekPredictions,
  mapPredictionToGame,
  fetchAvailableModels,
  ModelInfo
} from '@/lib/api';
import { Badge } from '@/components/ui/badge';
import { Loader2 } from 'lucide-react';

const Index = () => {
  const [selectedSport, setSelectedSport] = useState<SportType>('nfl');
  const [selectedSeason, setSelectedSeason] = useState(2025);
  const [selectedWeek, setSelectedWeek] = useState(3); // Current week for 2025
  const [selectedModel, setSelectedModel] = useState('elo');
  const [weekGames, setWeekGames] = useState<Game[]>([]);
  const [availableModels, setAvailableModels] = useState<ModelInfo[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [isUsingLiveData, setIsUsingLiveData] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [currentModelInfo, setCurrentModelInfo] = useState<ModelInfo | null>(null);

  // Load available models on mount
  useEffect(() => {
    const loadModels = async () => {
      const models = await fetchAvailableModels();
      setAvailableModels(models);
      // Set current model info
      const currentModel = models.find(m => m.id === selectedModel);
      setCurrentModelInfo(currentModel || null);
    };
    loadModels();
  }, []);

  // Load predictions when season, week, or model changes
  useEffect(() => {
    const loadPredictions = async () => {
      setIsLoading(true);
      setError(null);

      try {
        // Fetch predictions for the selected season, week, and model
        const predictions = await fetchWeekPredictions(selectedSeason, selectedWeek, selectedModel);

        if (predictions && predictions.length > 0) {
          // Map API predictions to Game type
          const mappedGames = predictions.map(pred => mapPredictionToGame(pred));
          setWeekGames(mappedGames);
          setIsUsingLiveData(true);

          // Update current model info
          const currentModel = availableModels.find(m => m.id === selectedModel);
          setCurrentModelInfo(currentModel || null);
        } else {
          // Fallback to mock data if API returns no data for this week
          const filteredMockGames = mockGames.filter(game => game.week === selectedWeek);
          setWeekGames(filteredMockGames);
          setIsUsingLiveData(false);

          if (predictions !== null && predictions.length === 0) {
            setError(`No games found for Week ${selectedWeek} of ${selectedSeason} season.`);
          }
        }
      } catch (err) {
        console.error('Failed to load predictions:', err);
        setError('Failed to load predictions. Using mock data.');

        // Fallback to mock data
        const filteredMockGames = mockGames.filter(game => game.week === selectedWeek);
        setWeekGames(filteredMockGames);
        setIsUsingLiveData(false);
      } finally {
        setIsLoading(false);
      }
    };

    loadPredictions();
  }, [selectedSeason, selectedWeek, selectedModel, availableModels]);

  // Handle model change
  const handleModelChange = (modelId: string) => {
    setSelectedModel(modelId);
  };

  return (
    <div className="min-h-screen bg-gradient-main text-foreground">
      <div className="container mx-auto p-6">
        {/* Header */}
        <DashboardHeader
          selectedSport={selectedSport}
          onSportChange={setSelectedSport}
          selectedSeason={selectedSeason}
          onSeasonChange={setSelectedSeason}
          selectedWeek={selectedWeek}
          onWeekChange={setSelectedWeek}
          totalWeeks={18}
          currentWeek={3}
        />

        {/* Model Selector and Status */}
        <div className="mb-8 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
          <div className="flex items-center gap-4">
            <ModelSelector
              selectedModel={selectedModel}
              onModelChange={handleModelChange}
              models={availableModels}
            />
            {isUsingLiveData && currentModelInfo && (
              <div className="flex items-center gap-2">
                <Badge variant="default" className="bg-green-500">
                  🔴 Live Predictions
                </Badge>

              </div>
            )}
          </div>

          {error && (
            <div className="text-sm text-red-500">
              {error}
            </div>
          )}
        </div>

        {/* Games Grid */}
        <div className="space-y-8">
          <div className="flex items-center justify-between">
            <h2 className="text-2xl font-bold">
              Week {selectedWeek} Games
              {isLoading && (
                <Loader2 className="inline-block ml-2 h-5 w-5 animate-spin" />
              )}
            </h2>
            <div className="flex items-center gap-2 text-sm text-muted-foreground">
              <span>{weekGames.length}</span>
              <span>{weekGames.length === 1 ? 'game' : 'games'} scheduled</span>
            </div>
          </div>

          {!isLoading && weekGames.length > 0 ? (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              {weekGames.map((game, index) => (
                <GameCard
                  key={`${game.id}-${selectedModel}`} // Force re-render on model change
                  game={game}
                  className={`animation-delay-${index * 100}`}
                  selectedWeek={selectedWeek}
                />
              ))}
            </div>
          ) : !isLoading ? (
            <div className="text-center py-12">
              <div className="text-6xl mb-4">📅</div>
              <h3 className="text-xl font-semibold text-foreground mb-2">
                No games scheduled
              </h3>
              <p className="text-muted-foreground">
                No games are scheduled for Week {selectedWeek}
              </p>
            </div>
          ) : null}
        </div>

        {/* Stats Summary */}
        {!isLoading && weekGames.length > 0 && currentModelInfo && (
          <div className="mt-12 bg-gradient-card rounded-lg p-6 shadow-card">
            <h3 className="text-lg font-semibold text-foreground mb-4">
              Week {selectedWeek} Summary - {currentModelInfo.name}
            </h3>
            <div className="grid grid-cols-1 md:grid-cols-4 gap-4 text-center">
              <div className="space-y-1">
                <div className="text-2xl font-bold text-sport-primary">{weekGames.length}</div>
                <div className="text-sm text-muted-foreground">Total Games</div>
              </div>
              <div className="space-y-1">
                <div className="text-2xl font-bold text-sport-accent">
                  {Math.round(weekGames.reduce((sum, game) =>
                    sum + Math.max(game.homeWinPercentage, game.awayWinPercentage), 0
                  ) / weekGames.length)}%
                </div>
                <div className="text-sm text-muted-foreground">Avg Max Win %</div>
              </div>
              <div className="space-y-1">
                <div className="text-2xl font-bold text-sport-secondary">
                  {weekGames.filter(game =>
                    Math.abs(game.homeWinPercentage - game.awayWinPercentage) <= 10
                  ).length}
                </div>
                <div className="text-sm text-muted-foreground">Close Games (&lt;10% diff)</div>
              </div>
              <div className="space-y-1">
                <div className="text-2xl font-bold text-green-500">
                  {weekGames.filter(game =>
                    Math.max(game.homeWinPercentage, game.awayWinPercentage) > 65
                  ).length}
                </div>
                <div className="text-sm text-muted-foreground">High Confidence</div>
              </div>
            </div>

            {isUsingLiveData && (
              <div className="mt-4 pt-4 border-t border-muted">
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-xs text-muted-foreground">
                  <div>
                    <span className="font-medium">Model:</span> {currentModelInfo.description}
                  </div>
                  <div className="text-right">
                    <span className="font-medium">Season Accuracy:</span> {(currentModelInfo.accuracy * 100).toFixed(1)}% |
                    <span className="font-medium"> Historical:</span> {(currentModelInfo.historical_accuracy * 100).toFixed(1)}%
                  </div>
                </div>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
};

export default Index;