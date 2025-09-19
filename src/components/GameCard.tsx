import { Game } from '@/types/sports';
import { Card, CardContent, CardHeader } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { WinPercentageBar } from './WinPercentageBar';
import { TeamFormPopover } from './TeamFormPopover';
import { cn } from '@/lib/utils';
import { ModelSelector } from './ModelSelector';

interface GameCardProps {
  game: Game;
  className?: string;
}

export const GameCard = ({ game, className }: GameCardProps) => {
  const formatGameTime = (date: Date) => {
    return date.toLocaleTimeString('en-US', {
      hour: 'numeric',
      minute: '2-digit',
      hour12: true
    });
  };

  const formatGameDate = (date: Date) => {
    return date.toLocaleDateString('en-US', {
      weekday: 'short',
      month: 'short',
      day: 'numeric'
    });
  };

  return (
    <Card className={cn(
      "bg-gradient-card shadow-card hover:shadow-elevated transition-smooth animate-slide-up",
      className
    )}>
      <CardHeader className="pb-3">
        <div className="flex justify-between items-center">
          <div className="flex items-center gap-3">
            <Badge variant="outline" className="text-xs font-medium">
              Week {game.week}
            </Badge>
            <TeamFormPopover
              homeTeam={game.homeTeam}
              awayTeam={game.awayTeam}
            />
            <ModelSelector pureElo={0} recentElo={0} injuryElo={0} currentModel={0} selectedModel={0} onModelChange={function (model: number): void {
              throw new Error('Function not implemented.');
            }}
            />
          </div>
          <div className="text-right text-xs text-muted-foreground">
            <div>{formatGameDate(game.gameDate)}</div>
            <div className="font-medium">{formatGameTime(game.gameDate)}</div>
          </div>
        </div>
      </CardHeader>

      <CardContent className="space-y-4">
        {/* Away Team */}
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div
                className="w-8 h-8 rounded-full flex items-center justify-center text-white font-bold text-sm shadow-sm"
                style={{ backgroundColor: game.awayTeam.primaryColor }}
              >
                {game.awayTeam.abbreviation}
              </div>
              <div>
                <div className="font-semibold text-foreground">
                  {game.awayTeam.city} {game.awayTeam.name}
                </div>
                <div className="flex items-center gap-2 text-xs text-muted-foreground">
                  <span>@ {game.homeTeam.city}</span>
                  <Badge variant="outline" className="text-xs px-1.5 py-0.5">
                    {game.awayTeam.wins}-{game.awayTeam.losses}
                  </Badge>
                </div>
              </div>
            </div>
          </div>
          <WinPercentageBar
            percentage={Number(game.awayWinPercentage.toFixed(2))}
            teamName="Win Probability"
          />
          {game.modelData && (
            <div className="mt-2 flex justify-between text-xs text-muted-foreground">
              <span>Elo: {game.modelData.awayElo.toFixed(0)}</span>
              <span>Elo: {game.modelData.homeElo.toFixed(0)}</span>
            </div>
          )}
        </div>

        <div className="border-l-2 border-muted mx-4 h-0"></div>

        {/* Home Team */}
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div
                className="w-8 h-8 rounded-full flex items-center justify-center text-white font-bold text-sm shadow-sm"
                style={{ backgroundColor: game.homeTeam.primaryColor }}
              >
                {game.homeTeam.abbreviation}
              </div>
              <div>
                <div className="font-semibold text-foreground">
                  {game.homeTeam.city} {game.homeTeam.name}
                </div>
                <div className="flex items-center gap-2 text-xs text-muted-foreground">
                  <span>Home</span>
                  <Badge variant="outline" className="text-xs px-1.5 py-0.5">
                    {game.homeTeam.wins}-{game.homeTeam.losses}
                  </Badge>
                </div>
              </div>
            </div>
          </div>
          <WinPercentageBar
            percentage={Number(game.homeWinPercentage.toFixed(2))}
            teamName="Win Probability"
          />
        </div>

        {game.isCompleted && game.homeScore !== undefined && game.awayScore !== undefined && (
          <div className="mt-4 pt-3 border-t border-muted">
            <div className="text-center">
              <Badge variant="secondary" className="font-bold">
                Final: {game.awayTeam.abbreviation} {game.awayScore} - {game.homeScore} {game.homeTeam.abbreviation}
              </Badge>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
};
