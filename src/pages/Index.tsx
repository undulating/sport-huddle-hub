// src/pages/Index.tsx
import { useState, useEffect } from 'react';
import { SportType, Game } from '@/types/sports';
import { mockSeason, mockGames } from '@/data/mockData';
import { DashboardHeader } from '@/components/DashboardHeader';
import { GameCard } from '@/components/GameCard';
import { fetchWeekPredictions, mapPredictionToGame } from '@/lib/api';
import { Badge } from '@/components/ui/badge';
import { Loader2 } from 'lucide-react';

const Index = () => {
  const [selectedSport, setSelectedSport] = useState<SportType>('nfl');
  const [selectedSeason, setSelectedSeason] = useState(2024);
  const [selectedWeek, setSelectedWeek] = useState(18);
  const [weekGames, setWeekGames] = useState<Game[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [isUsingLiveData, setIsUsingLiveData] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const loadPredictions = async () => {
      setIsLoading(true);
      setError(null);

      try {
        // Fetch predictions for the selected season and week
        const predictions = await fetchWeekPredictions(selectedSeason, selectedWeek);

        if (predictions && predictions.length > 0) {
          // Map API predictions to Game type
          const mappedGames = predictions.map(pred => mapPredictionToGame(pred));
          setWeekGames(mappedGames);
          setIsUsingLiveData(true);
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
        // Fallback to mock data on error
        const filteredMockGames = mockGames.filter(game => game.week === selectedWeek);
        setWeekGames(filteredMockGames);
        setIsUsingLiveData(false);
      } finally {
        setIsLoading(false);
      }
    };

    loadPredictions();
  }, [selectedSeason, selectedWeek]);

  return (
    <div className="min-h-screen bg-background">
      <div className="container mx-auto px-4 py-8 max-w-7xl">
        <DashboardHeader
          selectedSport={selectedSport}
          selectedSeason={selectedSeason}
          selectedWeek={selectedWeek}
          currentWeek={mockSeason.currentWeek}
          totalWeeks={mockSeason.totalWeeks}
          onSportChange={setSelectedSport}
          onSeasonChange={setSelectedSeason}
          onWeekChange={setSelectedWeek}
        />

        {/* Status Indicator */}
        {(isUsingLiveData || error) && (
          <div className="mt-4 flex items-center justify-center gap-2">
            {isUsingLiveData && (
              <Badge variant="default" className="animate-pulse">
                🔴 Live Elo Predictions
              </Badge>
            )}
            {error && (
              <Badge variant="secondary">
                📊 Using Mock Data
              </Badge>
            )}
          </div>
        )}

        {/* Games Grid */}
        <div className="mt-8">
          <div className="flex items-center justify-between mb-6">
            <h2 className="text-2xl font-bold text-foreground">
              Week {selectedWeek} Games
            </h2>
            <div className="flex items-center gap-4">
              {isLoading && (
                <div className="flex items-center gap-2 text-sm text-muted-foreground">
                  <Loader2 className="h-4 w-4 animate-spin" />
                  Loading predictions...
                </div>
              )}
              <div className="text-sm text-muted-foreground">
                {weekGames.length} {weekGames.length === 1 ? 'game' : 'games'} scheduled
              </div>
            </div>
          </div>

          {!isLoading && weekGames.length > 0 ? (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              {weekGames.map((game, index) => (
                <GameCard
                  key={game.id}
                  game={game}
                  className={`animation-delay-${index * 100}`}
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
        {!isLoading && weekGames.length > 0 && (
          <div className="mt-12 bg-gradient-card rounded-lg p-6 shadow-card">
            <h3 className="text-lg font-semibold text-foreground mb-4">
              Week Summary {isUsingLiveData && '(Live Predictions)'}
            </h3>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-center">
              <div className="space-y-1">
                <div className="text-2xl font-bold text-sport-primary">{weekGames.length}</div>
                <div className="text-sm text-muted-foreground">Total Games</div>
              </div>
              <div className="space-y-1">
                <div className="text-2xl font-bold text-sport-accent">
                  {Math.round(weekGames.reduce((sum, game) => sum + Math.max(game.homeWinPercentage, game.awayWinPercentage), 0) / weekGames.length)}%
                </div>
                <div className="text-sm text-muted-foreground">Avg Max Win %</div>
              </div>
              <div className="space-y-1">
                <div className="text-2xl font-bold text-sport-secondary">
                  {weekGames.filter(game => Math.abs(game.homeWinPercentage - game.awayWinPercentage) <= 10).length}
                </div>
                <div className="text-sm text-muted-foreground">Close Games (&lt;10% diff)</div>
              </div>
            </div>
            {isUsingLiveData && weekGames[0]?.modelData && (
              <div className="mt-4 pt-4 border-t border-muted">
                <div className="text-xs text-muted-foreground text-center">
                  Model: {weekGames[0].modelData.modelVersion} |
                  Accuracy: 62.5% on 2,743 games
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