import { SportType } from '@/types/sports';
import { availableSports } from '@/data/mockData';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';

interface SportSelectorProps {
  selectedSport: SportType;
  onSportChange: (sport: SportType) => void;
}

export const SportSelector = ({ selectedSport, onSportChange }: SportSelectorProps) => {
  return (
    <div className="flex gap-2">
      {availableSports.map((sport) => (
        <Button
          key={sport.id}
          variant={selectedSport === sport.id ? "default" : "outline"}
          onClick={() => onSportChange(sport.id)}
          className={cn(
            "flex items-center gap-2 transition-smooth hover:shadow-team",
            selectedSport === sport.id && "bg-gradient-sport text-white shadow-team"
          )}
        >
          <span className="text-lg">{sport.icon}</span>
          <span className="font-semibold">{sport.name}</span>
        </Button>
      ))}
    </div>
  );
};