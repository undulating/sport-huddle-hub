import { Player, Team } from '@/types/sports';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { TrendingUp } from 'lucide-react';
import { cn } from '@/lib/utils';

interface TeamFormPopoverProps {
  homeTeam: Team;
  awayTeam: Team;
}

const PlayerRow = ({ player }: { player: Player }) => (
  <div className="flex items-center justify-between py-2 px-3 hover:bg-muted/50 rounded-lg transition-smooth">
    <div className="flex items-center gap-3">
      <div className="w-8 h-8 bg-muted rounded-full flex items-center justify-center text-xs font-bold">
        {player.number}
      </div>
      <div>
        <div className="font-medium text-sm">{player.name}</div>
        <div className="text-xs text-muted-foreground">{player.position}</div>
      </div>
    </div>
    <div className="flex items-center gap-2">
      <div className="w-12 h-6 bg-muted/30 rounded flex items-center justify-center">
        <span className="text-xs text-muted-foreground">TBD</span>
      </div>
      <div className="text-xs text-muted-foreground">Form</div>
    </div>
  </div>
);

const TeamRoster = ({ team, className }: { team: Team; className?: string }) => (
  <div className={cn("space-y-2", className)}>
    <div className="flex items-center gap-2 px-3 py-2 border-b">
      <div 
        className="w-6 h-6 rounded-full flex items-center justify-center text-white font-bold text-xs"
        style={{ backgroundColor: team.primaryColor }}
      >
        {team.abbreviation}
      </div>
      <div className="font-semibold text-sm">{team.city} {team.name}</div>
      <Badge variant="outline" className="ml-auto text-xs">
        {team.wins}-{team.losses}
      </Badge>
    </div>
    <div className="max-h-48 overflow-y-auto space-y-1">
      {team.roster.map((player) => (
        <PlayerRow key={player.id} player={player} />
      ))}
    </div>
  </div>
);

export const TeamFormPopover = ({ homeTeam, awayTeam }: TeamFormPopoverProps) => {
  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button 
          variant="outline" 
          size="sm"
          className="gap-2 hover:bg-sport-primary/10 hover:border-sport-primary/30 transition-smooth"
        >
          <TrendingUp className="w-4 h-4" />
          <span className="text-xs font-medium">Team Form</span>
        </Button>
      </PopoverTrigger>
      <PopoverContent 
        className="w-96 p-0 bg-gradient-card shadow-elevated" 
        align="center"
      >
        <div className="p-4">
          <div className="flex items-center gap-2 mb-4">
            <TrendingUp className="w-5 h-5 text-sport-primary" />
            <h3 className="font-semibold">Player Form Ratings</h3>
          </div>
          
          <div className="space-y-4">
            <TeamRoster team={awayTeam} />
            <div className="border-t pt-4">
              <TeamRoster team={homeTeam} />
            </div>
          </div>
          
          <div className="mt-4 pt-3 border-t text-center">
            <p className="text-xs text-muted-foreground">
              Form ratings will be populated by backend analysis
            </p>
          </div>
        </div>
      </PopoverContent>
    </Popover>
  );
};