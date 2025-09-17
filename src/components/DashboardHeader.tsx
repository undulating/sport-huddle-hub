import { SportType } from '@/types/sports';
import { SportSelector } from './SportSelector';
import { SeasonSelector } from './SeasonSelector';
import { WeekSelector } from './WeekSelector';
import { availableSports } from '@/data/mockData';

interface DashboardHeaderProps {
  selectedSport: SportType;
  selectedSeason: number;
  selectedWeek: number;
  currentWeek: number;
  totalWeeks: number;
  onSportChange: (sport: SportType) => void;
  onSeasonChange: (season: number) => void;
  onWeekChange: (week: number) => void;
}

export const DashboardHeader = ({
  selectedSport,
  selectedSeason,
  selectedWeek,
  currentWeek,
  totalWeeks,
  onSportChange,
  onSeasonChange,
  onWeekChange
}: DashboardHeaderProps) => {
  const currentSportData = availableSports.find(s => s.id === selectedSport);

  return (
    <div className="space-y-6">
      {/* Title Section */}
      <div className="text-center">
        <h1 className="text-4xl font-bold bg-gradient-sport bg-clip-text text-transparent mb-2">
          Sports Dashboard
        </h1>
        <p className="text-muted-foreground">
          Track team performance and win probabilities across seasons
        </p>
      </div>

      {/* Controls Section */}
      <div className="bg-gradient-card rounded-lg p-6 shadow-card">
        <div className="flex flex-wrap items-center justify-between gap-4">
          {/* Sport Selector */}
          <div className="flex items-center gap-3">
            <span className="text-sm font-medium text-muted-foreground">Sport:</span>
            <SportSelector 
              selectedSport={selectedSport}
              onSportChange={onSportChange}
            />
          </div>

          {/* Season & Week Controls */}
          <div className="flex items-center gap-6">
            <SeasonSelector 
              seasons={currentSportData?.seasons || []}
              selectedSeason={selectedSeason}
              onSeasonChange={onSeasonChange}
            />
            
            <WeekSelector 
              totalWeeks={totalWeeks}
              currentWeek={currentWeek}
              selectedWeek={selectedWeek}
              onWeekChange={onWeekChange}
            />
          </div>
        </div>
      </div>
    </div>
  );
};