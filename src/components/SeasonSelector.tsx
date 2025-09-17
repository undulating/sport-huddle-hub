import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';

interface SeasonSelectorProps {
  seasons: number[];
  selectedSeason: number;
  onSeasonChange: (season: number) => void;
}

export const SeasonSelector = ({ seasons, selectedSeason, onSeasonChange }: SeasonSelectorProps) => {
  return (
    <div className="flex items-center gap-2">
      <span className="text-sm font-medium text-muted-foreground">Season:</span>
      <Select 
        value={selectedSeason.toString()} 
        onValueChange={(value) => onSeasonChange(parseInt(value))}
      >
        <SelectTrigger className="w-24 bg-gradient-card shadow-card">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {seasons.map((season) => (
            <SelectItem key={season} value={season.toString()}>
              {season}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </div>
  );
};