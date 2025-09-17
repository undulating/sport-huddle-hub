export interface Team {
  id: string;
  name: string;
  city: string;
  abbreviation: string;
  logo?: string;
  primaryColor: string;
  secondaryColor: string;
  conference?: string;
  division?: string;
}

export interface Game {
  id: string;
  week: number;
  homeTeam: Team;
  awayTeam: Team;
  homeWinPercentage: number;
  awayWinPercentage: number;
  gameDate: Date;
  isCompleted: boolean;
  homeScore?: number;
  awayScore?: number;
}

export interface Season {
  year: number;
  sport: SportType;
  currentWeek: number;
  totalWeeks: number;
  games: Game[];
}

export type SportType = 'nfl' | 'nba' | 'mlb';

export interface Sport {
  id: SportType;
  name: string;
  icon: string;
  seasons: number[];
  currentSeason: number;
}