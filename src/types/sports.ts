export interface Player {
  id: string;
  name: string;
  position: string;
  number: number;
  formRating?: number; // 1-10 scale, will be filled by backend
}

export interface ModelData {
  homeElo: number;
  awayElo: number;
  predictedSpread: number;
  confidence: number;
  modelVersion: string;
  modelUsed?: string;
}

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
  wins: number;
  losses: number;
  roster: Player[];
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
  modelData?: ModelData;
  homeMoneyline?: number;
  awayMoneyline?: number;
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