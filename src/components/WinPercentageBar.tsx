import { Progress } from '@/components/ui/progress';
import { cn } from '@/lib/utils';

interface WinPercentageBarProps {
  percentage: number;
  teamName: string;
  className?: string;
}

export const WinPercentageBar = ({ percentage, teamName, className }: WinPercentageBarProps) => {
  const getPercentageColor = (pct: number) => {
    if (pct >= 70) return 'bg-win-high';
    if (pct >= 40) return 'bg-win-medium';
    return 'bg-win-low';
  };

  const getPercentageTextColor = (pct: number) => {
    if (pct >= 70) return 'text-win-high';
    if (pct >= 40) return 'text-win-medium';
    return 'text-win-low';
  };

  return (
    <div className={cn("space-y-1", className)}>
      <div className="flex justify-between items-center">
        <span className="text-sm font-medium text-foreground">{teamName}</span>
        <span className={cn("text-sm font-bold", getPercentageTextColor(percentage))}>
          {percentage}%
        </span>
      </div>
      <div className="relative">
        <Progress 
          value={percentage} 
          className="h-2 bg-muted/30"
        />
        <div 
          className={cn(
            "absolute top-0 left-0 h-2 rounded-full transition-smooth",
            getPercentageColor(percentage)
          )}
          style={{ width: `${percentage}%` }}
        />
      </div>
    </div>
  );
};