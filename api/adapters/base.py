"""Base adapter protocol for data providers."""
from abc import ABC, abstractmethod
from typing import List, Optional, Dict, Any
from datetime import datetime

from api.schemas.provider import (
    TeamDTO, GameDTO, OddsDTO, InjuryDTO, WeatherDTO
)


class ProviderAdapter(ABC):
    """Abstract base class for provider adapters."""
    
    def __init__(self, api_key: Optional[str] = None):
        """Initialize adapter with optional API key."""
        self.api_key = api_key
        self.provider_name = self.__class__.__name__.replace("Adapter", "")
    
    @abstractmethod
    def get_teams(self) -> List[TeamDTO]:
        """Get all NFL teams."""
        pass
    
    @abstractmethod
    def get_games(self, season: int, week: Optional[int] = None) -> List[GameDTO]:
        """Get games for a season/week."""
        pass
    
    @abstractmethod
    def get_odds(self, season: int, week: int) -> List[OddsDTO]:
        """Get betting odds for games."""
        pass
    
    @abstractmethod
    def get_injuries(self, season: int, week: int) -> List[InjuryDTO]:
        """Get injury reports."""
        pass
    
    @abstractmethod
    def get_weather(self, game_external_id: str) -> Optional[WeatherDTO]:
        """Get weather forecast for a game."""
        pass


class ProviderRegistry:
    """Registry for provider adapters."""
    
    _adapters: Dict[str, type] = {}
    
    @classmethod
    def register(cls, name: str, adapter_class: type):
        """Register a provider adapter."""
        cls._adapters[name] = adapter_class
    
    @classmethod
    def get_adapter(cls, name: str, **kwargs) -> ProviderAdapter:
        """Get an instance of a provider adapter."""
        if name not in cls._adapters:
            raise ValueError(f"Unknown provider: {name}")
        return cls._adapters[name](**kwargs)
    
    @classmethod
    def list_providers(cls) -> List[str]:
        """List available providers."""
        return list(cls._adapters.keys())
