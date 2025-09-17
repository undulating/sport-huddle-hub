import { Team, Game, Season, Sport, SportType } from '@/types/sports';

export const mockTeams: Record<string, Team> = {
  'KC': {
    id: 'KC',
    name: 'Chiefs',
    city: 'Kansas City',
    abbreviation: 'KC',
    primaryColor: '#E31837',
    secondaryColor: '#FFB81C',
    conference: 'AFC',
    division: 'West'
  },
  'BUF': {
    id: 'BUF',
    name: 'Bills',
    city: 'Buffalo',
    abbreviation: 'BUF',
    primaryColor: '#00338D',
    secondaryColor: '#C60C30',
    conference: 'AFC',
    division: 'East'
  },
  'SF': {
    id: 'SF',
    name: '49ers',
    city: 'San Francisco',
    abbreviation: 'SF',
    primaryColor: '#AA0000',
    secondaryColor: '#B3995D',
    conference: 'NFC',
    division: 'West'
  },
  'DAL': {
    id: 'DAL',
    name: 'Cowboys',
    city: 'Dallas',
    abbreviation: 'DAL',
    primaryColor: '#003594',
    secondaryColor: '#869397',
    conference: 'NFC',
    division: 'East'
  },
  'MIA': {
    id: 'MIA',
    name: 'Dolphins',
    city: 'Miami',
    abbreviation: 'MIA',
    primaryColor: '#008E97',
    secondaryColor: '#FC4C02',
    conference: 'AFC',
    division: 'East'
  },
  'PHI': {
    id: 'PHI',
    name: 'Eagles',
    city: 'Philadelphia',
    abbreviation: 'PHI',
    primaryColor: '#004C54',
    secondaryColor: '#A5ACAF',
    conference: 'NFC',
    division: 'East'
  }
};

export const mockGames: Game[] = [
  {
    id: '1',
    week: 18,
    homeTeam: mockTeams['KC'],
    awayTeam: mockTeams['BUF'],
    homeWinPercentage: 68,
    awayWinPercentage: 32,
    gameDate: new Date('2024-01-07T13:00:00'),
    isCompleted: false
  },
  {
    id: '2',
    week: 18,
    homeTeam: mockTeams['SF'],
    awayTeam: mockTeams['DAL'],
    homeWinPercentage: 75,
    awayWinPercentage: 25,
    gameDate: new Date('2024-01-07T16:30:00'),
    isCompleted: false
  },
  {
    id: '3',
    week: 18,
    homeTeam: mockTeams['MIA'],
    awayTeam: mockTeams['PHI'],
    homeWinPercentage: 45,
    awayWinPercentage: 55,
    gameDate: new Date('2024-01-07T20:20:00'),
    isCompleted: false
  }
];

export const mockSeason: Season = {
  year: 2024,
  sport: 'nfl',
  currentWeek: 18,
  totalWeeks: 18,
  games: mockGames
};

export const availableSports: Sport[] = [
  {
    id: 'nfl',
    name: 'NFL',
    icon: '🏈',
    seasons: [2023, 2024],
    currentSeason: 2024
  },
  {
    id: 'nba',
    name: 'NBA',
    icon: '🏀',
    seasons: [2023, 2024],
    currentSeason: 2024
  },
  {
    id: 'mlb',
    name: 'MLB',
    icon: '⚾',
    seasons: [2023, 2024],
    currentSeason: 2024
  }
];