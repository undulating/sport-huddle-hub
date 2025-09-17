import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Badge } from '@/components/ui/badge';

interface WeekSelectorProps {
  totalWeeks: number;
  currentWeek: number;
  selectedWeek: number;
  onWeekChange: (week: number) => void;
}

export const WeekSelector = ({ totalWeeks, currentWeek, selectedWeek, onWeekChange }: WeekSelectorProps) => {
  const weeks = Array.from({ length: totalWeeks }, (_, i) => i + 1);

  return (
    <div className="flex items-center gap-3">
      <div className="flex items-center gap-2">
        <span className="text-sm font-medium text-muted-foreground">Week:</span>
        <Select 
          value={selectedWeek.toString()} 
          onValueChange={(value) => onWeekChange(parseInt(value))}
        >
          <SelectTrigger className="w-20 bg-gradient-card shadow-card">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {weeks.map((week) => (
              <SelectItem key={week} value={week.toString()}>
                {week}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>
      
      {selectedWeek === currentWeek && (
        <Badge variant="secondary" className="bg-sport-accent text-white animate-pulse-win">
          Current Week
        </Badge>
      )}
    </div>
  );
};