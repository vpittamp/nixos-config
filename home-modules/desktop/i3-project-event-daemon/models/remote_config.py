# Feature 087: Remote Project Environment Support
# RemoteConfig Pydantic model for SSH-based remote projects
# Created: 2025-11-22

"""
RemoteConfig Pydantic model for SSH connection parameters.

Provides validation for remote project environments accessed via SSH.
Supports Tailscale hostnames, custom ports, and absolute remote paths.
"""

from pydantic import BaseModel, Field, field_validator


class RemoteConfig(BaseModel):
    """Remote environment configuration for SSH-based projects."""

    enabled: bool = Field(
        default=False,
        description="Enable remote mode for this project"
    )

    host: str = Field(
        ...,
        min_length=1,
        description="SSH hostname (Tailscale FQDN or IP)"
    )

    user: str = Field(
        ...,
        min_length=1,
        description="SSH username"
    )

    working_dir: str = Field(
        ...,
        min_length=1,
        description="Remote working directory (absolute path)"
    )

    port: int = Field(
        default=22,
        ge=1,
        le=65535,
        description="SSH port"
    )

    @field_validator('working_dir')
    @classmethod
    def validate_remote_dir(cls, v: str) -> str:
        """Validate remote directory is absolute path."""
        if not v.startswith('/'):
            raise ValueError(
                f"Remote working_dir must be absolute path (starts with '/'), got: {v}"
            )
        return v

    def to_ssh_host(self) -> str:
        """Format as SSH host string for connection."""
        if self.port == 22:
            return f"{self.user}@{self.host}"
        return f"{self.user}@{self.host}:{self.port}"

    class Config:
        json_schema_extra = {
            "example": {
                "enabled": True,
                "host": "hetzner-sway.tailnet",
                "user": "vpittamp",
                "working_dir": "/home/vpittamp/dev/my-app",
                "port": 22
            }
        }
