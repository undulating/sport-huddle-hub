import { useState } from 'react';
import { SportType } from '@/types/sports';
import { mockSeason, mockGames } from '@/data/mockData';
import { DashboardHeader } from '@/components/DashboardHeader';
import { GameCard } from '@/components/GameCard';

const Index = () => {
  const [selectedSport, setSelectedSport] = useState<SportType>('nfl');
  const [selectedSeason, setSelectedSeason] = useState(2024);
  const [selectedWeek, setSelectedWeek] = useState(18);

  // Filter games for selected week
  const weekGames = mockGames.filter(game => game.week === selectedWeek);

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

        {/* Games Grid */}
        <div className="mt-8">
          <div className="flex items-center justify-between mb-6">
            <h2 className="text-2xl font-bold text-foreground">
              Week {selectedWeek} Games
            </h2>
            <div className="text-sm text-muted-foreground">
              {weekGames.length} {weekGames.length === 1 ? 'game' : 'games'} scheduled
            </div>
          </div>

          {weekGames.length > 0 ? (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              {weekGames.map((game, index) => (
                <GameCard 
                  key={game.id} 
                  game={game}
                  className={`animation-delay-${index * 100}`}
                />
              ))}
            </div>
          ) : (
            <div className="text-center py-12">
              <div className="text-6xl mb-4">📅</div>
              <h3 className="text-xl font-semibold text-foreground mb-2">
                No games scheduled
              </h3>
              <p className="text-muted-foreground">
                No games are scheduled for Week {selectedWeek}
              </p>
            </div>
          )}
        </div>

        {/* Stats Summary */}
        {weekGames.length > 0 && (
          <div className="mt-12 bg-gradient-card rounded-lg p-6 shadow-card">
            <h3 className="text-lg font-semibold text-foreground mb-4">Week Summary</h3>
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
                <div className="text-sm text-muted-foreground">Close Games</div>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default Index;
