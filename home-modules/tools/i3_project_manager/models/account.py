"""
Feature 100: AccountConfig - GitHub Account Configuration

Configured GitHub account or organization with base directory path.
Storage: ~/.config/i3/accounts.json
"""

from pydantic import BaseModel, Field, field_validator
from pathlib import Path
import re


class AccountConfig(BaseModel):
    """
    GitHub account or organization configuration.

    Each account has a dedicated base directory (e.g., ~/repos/vpittamp).
    Repositories for that account are cloned as subdirectories.

    Fields:
        name: GitHub account/org name (e.g., "vpittamp", "PittampalliOrg")
        path: Base directory path (e.g., "~/repos/vpittamp")
        is_default: Default account for clone without explicit account
        ssh_host: SSH host alias (default: "github.com")
    """
    name: str = Field(
        ...,
        min_length=1,
        max_length=39,
        description="GitHub account/org name"
    )
    path: str = Field(
        ...,
        min_length=1,
        description="Base directory path (absolute or ~)"
    )
    is_default: bool = Field(
        default=False,
        description="Default account for clone without explicit account"
    )
    ssh_host: str = Field(
        default="github.com",
        description="SSH host alias for this account"
    )

    @field_validator('name')
    @classmethod
    def validate_name(cls, v: str) -> str:
        """Validate GitHub username format."""
        if not re.match(r'^[a-zA-Z0-9][a-zA-Z0-9-]*$', v):
            raise ValueError('Invalid GitHub username format')
        return v

    @field_validator('path')
    @classmethod
    def validate_path(cls, v: str) -> str:
        """Ensure path is absolute."""
        expanded = Path(v).expanduser()
        if not expanded.is_absolute():
            raise ValueError('Path must be absolute')
        return str(expanded)

    @property
    def expanded_path(self) -> Path:
        """Return expanded absolute path."""
        return Path(self.path).expanduser()


class AccountsStorage(BaseModel):
    """
    Storage schema for accounts.json.

    Location: ~/.config/i3/accounts.json
    """
    version: int = Field(default=1, description="Schema version")
    accounts: list[AccountConfig] = Field(
        default_factory=list,
        description="Configured accounts"
    )

    def get_default_account(self) -> AccountConfig | None:
        """Get the default account, or None if not set."""
        for account in self.accounts:
            if account.is_default:
                return account
        return None

    def get_account_by_name(self, name: str) -> AccountConfig | None:
        """Find account by name."""
        for account in self.accounts:
            if account.name == name:
                return account
        return None

    def add_account(self, account: AccountConfig) -> None:
        """Add an account, ensuring no duplicate names."""
        if self.get_account_by_name(account.name):
            raise ValueError(f"Account '{account.name}' already exists")

        # If this is the first account or is_default, ensure only one default
        if account.is_default or not self.accounts:
            for existing in self.accounts:
                existing.is_default = False
            if not account.is_default and not self.accounts:
                account.is_default = True

        self.accounts.append(account)

    def remove_account(self, name: str) -> bool:
        """Remove an account by name. Returns True if removed."""
        for i, account in enumerate(self.accounts):
            if account.name == name:
                self.accounts.pop(i)
                return True
        return False
