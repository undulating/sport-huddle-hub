import { Game } from '@/types/sports';
import { Card, CardContent, CardHeader } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { WinPercentageBar } from './WinPercentageBar';
import { TeamFormPopover } from './TeamFormPopover';
import { cn } from '@/lib/utils';
import { Input } from '@/components/ui/input'; // ⟵ shadcn Input

import { useMemo, useState } from 'react';

interface GameCardProps {
  game: Game;
  className?: string;
  selectedWeek?: number;
}

export const GameCard = ({ game, className, selectedWeek }: GameCardProps) => {
  const [awayStake, setAwayStake] = useState<string>('');
  const [homeStake, setHomeStake] = useState<string>('');

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

  // --- Moneyline math helpers ---
  const toNumber = (v: string) => {
    const n = parseFloat(v);
    return Number.isFinite(n) && n >= 0 ? n : 0;
  };

  /**
   * Returns { payout, profit } given American odds and a stake.
   * payout = stake + profit
   */
  const calcMoneyline = (odds?: number | null, stakeStr?: string) => {
    if (odds == null) return { payout: 0, profit: 0 };
    const stake = toNumber(stakeStr ?? '');
    if (stake <= 0) return { payout: 0, profit: 0 };

    let profit = 0;
    if (odds > 0) {
      profit = (stake * odds) / 100;
    } else if (odds < 0) {
      profit = (stake * 100) / Math.abs(odds);
    }
    const payout = stake + profit;
    return { payout, profit };
  };

  const fmtUSD = (n: number) =>
    n.toLocaleString('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 2 });

  const awayCalc = useMemo(
    () => calcMoneyline(game.awayMoneyline, awayStake),
    [game.awayMoneyline, awayStake]
  );
  const homeCalc = useMemo(
    () => calcMoneyline(game.homeMoneyline, homeStake),
    [game.homeMoneyline, homeStake]
  );

  const MoneylineRow = ({
    label,
    odds,
    stake,
    setStake,
    payout,
    profit,
    indent = true
  }: {
    label: string;
    odds?: number | null;
    stake: string;
    setStake: (s: string) => void;
    payout: number;
    profit: number;
    indent?: boolean;
  }) => {
    const disabled = odds == null;
    return (
      <div className={cn('text-xs text-muted-foreground', indent && 'pl-11')}>
        <div className="flex items-center gap-2 flex-wrap">
          <span>
            {label}:{' '}
            <span className="font-semibold">
              {odds != null ? (odds > 0 ? `+${odds}` : odds) : '—'}
            </span>
          </span>

          {/* stake input */}
          <div className="flex items-center gap-1">
            <span className="opacity-80">$</span>
            <Input
              type="number"
              inputMode="decimal"
              step="5"
              min="0"
              placeholder="0"
              className="h-7 w-24 px-2 py-1 text-xs"
              value={stake}
              onChange={(e) => setStake(e.target.value)}
              disabled={disabled}
            />
            <span className="opacity-80">stake</span>
          </div>

          {/* results */}
          <div className={cn('flex items-center gap-2', disabled && 'opacity-50')}>
            <span>Payout: <span className="font-semibold">{fmtUSD(payout)}</span></span>
            <span>Profit: <span className="font-semibold">{fmtUSD(profit)}</span></span>
          </div>
        </div>
      </div>
    );
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
              Week {selectedWeek ?? game.week}
            </Badge>
            <TeamFormPopover
              homeTeam={game.homeTeam}
              awayTeam={game.awayTeam}
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
          {typeof game.awayMoneyline !== 'undefined' && (
            <MoneylineRow
              label="Moneyline"
              odds={game.awayMoneyline}
              stake={awayStake}
              setStake={setAwayStake}
              payout={awayCalc.payout}
              profit={awayCalc.profit}
            />
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
          {typeof game.homeMoneyline !== 'undefined' && (
            <MoneylineRow
              label="Moneyline"
              odds={game.homeMoneyline}
              stake={homeStake}
              setStake={setHomeStake}
              payout={homeCalc.payout}
              profit={homeCalc.profit}
            />
          )}
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
