"""Player model."""
from sqlalchemy import Column, String, Integer, Float, Boolean, DateTime, Index, JSON
# If you prefer JSONB on Postgres, you can swap:
# from sqlalchemy.dialects.postgresql import JSONB as JSON

from api.storage.base import Base


class Player(Base):
    """NFL player master + season snapshot + rolled-up stats."""

    __tablename__ = "players"
    __table_args__ = (
        Index("idx_players_team_season", "team_abbr", "season"),
        Index("idx_players_name", "name"),
        Index("idx_players_espn_id", "espn_id"),
        Index("idx_players_active", "active"),
    )

    id = Column(Integer, primary_key=True, index=True)

    # Identity
    espn_id = Column(String)                      # external id, may be null
    name = Column(String, nullable=False)         # canonical name
    display_name = Column(String)                 # preferred/display name
    team_abbr = Column(String)                    # e.g., PHI, DAL (no FK here)
    position = Column(String)                     # e.g., QB
    position_group = Column(String)               # e.g., OFF, DEF, ST
    jersey_number = Column(String)
    height = Column(String)                       # stored as raw string (e.g., "6'2\"")
    weight = Column(String)                       # stored as raw string (e.g., "215")
    age = Column(Integer)
    experience_years = Column(Integer)
    college = Column(String)
    headshot_url = Column(String)
    active = Column(Boolean)

    # Roll-up appearance
    games_played = Column(Integer)

    # Passing
    passing_yards = Column(Integer)
    passing_tds = Column(Integer)
    completions = Column(Integer)
    attempts = Column(Integer)
    interceptions = Column(Integer)
    passer_rating = Column(Float)

    # Rushing
    rushing_yards = Column(Integer)
    rushing_tds = Column(Integer)
    carries = Column(Integer)
    yards_per_carry = Column(Float)

    # Receiving
    receiving_yards = Column(Integer)
    receiving_tds = Column(Integer)
    receptions = Column(Integer)
    targets = Column(Integer)
    yards_per_reception = Column(Float)

    # Fantasy
    fantasy_points_std = Column(Float)
    fantasy_points_ppr = Column(Float)

    # Bookkeeping
    last_updated = Column(DateTime)               # naive timestamp (matches your DDL)
    season = Column(Integer)                      # season snapshot for these stats
    full_stats = Column(JSON)                     # raw blob from provider(s)

    def __repr__(self) -> str:
        tn = self.team_abbr or "-"
        pos = self.position or "-"
        yr = self.season or "-"
        return f"<Player id={self.id} {self.name} ({pos}, {tn}, {yr})>"
