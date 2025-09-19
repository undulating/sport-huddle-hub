import { Team, Game, Season, Sport, SportType, Player } from '@/types/sports';

// Mock roster data for teams
const mockRosters: Record<string, Player[]> = {
  'KC': [
    { id: '1', name: 'Patrick Mahomes', position: 'QB', number: 15 },
    { id: '2', name: 'Travis Kelce', position: 'TE', number: 87 },
    { id: '3', name: 'Tyreek Hill', position: 'WR', number: 10 },
    { id: '4', name: 'Clyde Edwards-Helaire', position: 'RB', number: 25 },
    { id: '5', name: 'Chris Jones', position: 'DT', number: 95 },
  ],
  'BUF': [
    { id: '6', name: 'Josh Allen', position: 'QB', number: 17 },
    { id: '7', name: 'Stefon Diggs', position: 'WR', number: 14 },
    { id: '8', name: 'James Cook', position: 'RB', number: 4 },
    { id: '9', name: 'Dawson Knox', position: 'TE', number: 88 },
    { id: '10', name: 'Von Miller', position: 'LB', number: 40 },
  ],
  'SF': [
    { id: '11', name: 'Brock Purdy', position: 'QB', number: 13 },
    { id: '12', name: 'Christian McCaffrey', position: 'RB', number: 23 },
    { id: '13', name: 'Deebo Samuel', position: 'WR', number: 19 },
    { id: '14', name: 'George Kittle', position: 'TE', number: 85 },
    { id: '15', name: 'Nick Bosa', position: 'DE', number: 97 },
  ],
  'DAL': [
    { id: '16', name: 'Dak Prescott', position: 'QB', number: 4 },
    { id: '17', name: 'Ezekiel Elliott', position: 'RB', number: 21 },
    { id: '18', name: 'CeeDee Lamb', position: 'WR', number: 88 },
    { id: '19', name: 'Jake Ferguson', position: 'TE', number: 87 },
    { id: '20', name: 'Micah Parsons', position: 'LB', number: 11 },
  ],
  'MIA': [
    { id: '21', name: 'Tua Tagovailoa', position: 'QB', number: 1 },
    { id: '22', name: 'Tyreek Hill', position: 'WR', number: 10 },
    { id: '23', name: 'Raheem Mostert', position: 'RB', number: 31 },
    { id: '24', name: 'Mike Gesicki', position: 'TE', number: 88 },
    { id: '25', name: 'Xavien Howard', position: 'CB', number: 25 },
  ],
  'PHI': [
    { id: '26', name: 'Jalen Hurts', position: 'QB', number: 1 },
    { id: '27', name: 'Saquon Barkley', position: 'RB', number: 26 },
    { id: '28', name: 'A.J. Brown', position: 'WR', number: 11 },
    { id: '29', name: 'Dallas Goedert', position: 'TE', number: 88 },
    { id: '30', name: 'Haason Reddick', position: 'LB', number: 7 },
  ],
};

export const mockTeams: Record<string, Team> = {
  'KC': {
    id: 'KC',
    name: 'Chiefs',
    city: 'Kansas City',
    abbreviation: 'KC',
    primaryColor: '#E31837',
    secondaryColor: '#FFB81C',
    conference: 'AFC',
    division: 'West',
    wins: 14,
    losses: 3,
    roster: mockRosters['KC']
  },
  'BUF': {
    id: 'BUF',
    name: 'Bills',
    city: 'Buffalo',
    abbreviation: 'BUF',
    primaryColor: '#00338D',
    secondaryColor: '#C60C30',
    conference: 'AFC',
    division: 'East',
    wins: 13,
    losses: 4,
    roster: mockRosters['BUF']
  },
  'SF': {
    id: 'SF',
    name: '49ers',
    city: 'San Francisco',
    abbreviation: 'SF',
    primaryColor: '#AA0000',
    secondaryColor: '#B3995D',
    conference: 'NFC',
    division: 'West',
    wins: 11,
    losses: 6,
    roster: mockRosters['SF']
  },
  'DAL': {
    id: 'DAL',
    name: 'Cowboys',
    city: 'Dallas',
    abbreviation: 'DAL',
    primaryColor: '#003594',
    secondaryColor: '#869397',
    conference: 'NFC',
    division: 'East',
    wins: 7,
    losses: 10,
    roster: mockRosters['DAL']
  },
  'MIA': {
    id: 'MIA',
    name: 'Dolphins',
    city: 'Miami',
    abbreviation: 'MIA',
    primaryColor: '#008E97',
    secondaryColor: '#FC4C02',
    conference: 'AFC',
    division: 'East',
    wins: 8,
    losses: 9,
    roster: mockRosters['MIA']
  },
  'PHI': {
    id: 'PHI',
    name: 'Eagles',
    city: 'Philadelphia',
    abbreviation: 'PHI',
    primaryColor: '#004C54',
    secondaryColor: '#A5ACAF',
    conference: 'NFC',
    division: 'East',
    wins: 14,
    losses: 3,
    roster: mockRosters['PHI']
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

// src/data/mockData.ts - Update just the availableSports array

export const availableSports: Sport[] = [
  {
    id: 'nfl',
    name: 'NFL',
    icon: '🏈',
    // Include all seasons including future 2025
    seasons: [2015, 2016, 2017, 2018, 2019, 2020, 2021, 2022, 2023, 2024, 2025],
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