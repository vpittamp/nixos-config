# Data Model: Remote Project Environment Support

**Feature**: 087-ssh-projects | **Date**: 2025-11-22
**Purpose**: Define data structures for remote project configuration

## Overview

This feature extends the existing `Project` model with an optional `remote` field containing SSH connection parameters. The extension follows Pydantic best practices for validation, serialization, and backward compatibility.

## Entity Definitions

### RemoteConfig

**Purpose**: SSH connection parameters for remote project environments

**Python (Pydantic)**:
```python
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
```

**TypeScript (Zod Schema)**:
```typescript
import { z } from "zod";

export const RemoteConfigSchema = z.object({
  enabled: z.boolean().default(false),
  host: z.string().min(1, "Host is required"),
  user: z.string().min(1, "User is required"),
  working_dir: z.string()
    .min(1, "Working directory is required")
    .refine((val) => val.startsWith("/"), {
      message: "Remote working_dir must be absolute path (starts with '/')"
    }),
  port: z.number().int().min(1).max(65535).default(22),
});

export type RemoteConfig = z.infer<typeof RemoteConfigSchema>;
```

**Validation Rules**:
- `enabled`: Boolean flag, defaults to `false` (opt-in for remote mode)
- `host`: Non-empty string, supports Tailscale FQDNs (e.g., `hetzner-sway.tailnet`) or IPs
- `user`: Non-empty string, SSH username for authentication
- `working_dir`: Absolute path (must start with `/`), remote project directory
- `port`: Integer 1-65535, defaults to 22 (standard SSH port)

**Error Messages**:
- Missing host: `"Host is required for remote configuration"`
- Missing user: `"User is required for remote configuration"`
- Missing working_dir: `"Working directory is required for remote configuration"`
- Relative path: `"Remote working_dir must be absolute path (starts with '/'), got: <value>"`
- Invalid port: `"Port must be between 1 and 65535, got: <value>"`

### Project (Extended)

**Purpose**: Project definition with optional remote configuration

**Python (Pydantic) - Changes Only**:
```python
from typing import Optional
from .remote_config import RemoteConfig  # New import

class Project(BaseModel):
    """Project definition with metadata."""

    name: str = Field(..., min_length=1, pattern=r'^[a-zA-Z0-9_-]+$')
    directory: str = Field(..., min_length=1)
    display_name: str = Field(..., min_length=1)
    icon: str = Field(default="📁")
    created_at: datetime = Field(default_factory=datetime.now)
    updated_at: datetime = Field(default_factory=datetime.now)
    scoped_classes: List[str] = Field(default_factory=list)

    # NEW: Optional remote configuration
    remote: Optional[RemoteConfig] = Field(
        default=None,
        description="Remote environment config (SSH-based)"
    )

    def is_remote(self) -> bool:
        """Check if this is a remote project."""
        return self.remote is not None and self.remote.enabled

    def get_effective_directory(self) -> str:
        """Get directory path (remote working_dir if remote, else local directory)."""
        if self.is_remote():
            return self.remote.working_dir
        return self.directory

    # Existing methods remain unchanged (save_to_file, load_from_file, list_all, etc.)
```

**TypeScript (Zod Schema) - Changes Only**:
```typescript
import { RemoteConfigSchema } from "./remote-config.ts";

export const ProjectSchema = z.object({
  name: z.string().min(1).regex(/^[a-zA-Z0-9_-]+$/),
  directory: z.string().min(1),
  display_name: z.string().min(1),
  icon: z.string().default("📁"),
  created_at: z.string().datetime(),
  updated_at: z.string().datetime(),
  scoped_classes: z.array(z.string()).default([]),

  // NEW: Optional remote configuration
  remote: RemoteConfigSchema.optional(),
});

export type Project = z.infer<typeof ProjectSchema>;
```

**New Methods**:
- `is_remote()`: Returns `true` if remote configuration exists and is enabled
- `get_effective_directory()`: Returns remote working_dir for remote projects, else local directory

**Backward Compatibility**:
- `remote` field is optional (`Optional[RemoteConfig]` in Python, `.optional()` in Zod)
- Existing local-only projects (no `remote` field) remain valid
- Default value is `None`/`undefined`, indicating local project

## JSON Serialization

### Local Project (Existing Format - No Changes)

```json
{
  "name": "nixos",
  "directory": "/home/vpittamp/nixos",
  "display_name": "NixOS Configuration",
  "icon": "❄️",
  "created_at": "2025-11-22T10:00:00.000Z",
  "updated_at": "2025-11-22T10:00:00.000Z",
  "scoped_classes": ["Ghostty", "Code"]
}
```

### Remote Project (New Format)

```json
{
  "name": "hetzner-dev",
  "directory": "/home/vpittamp/projects/hetzner-dev",
  "display_name": "Hetzner Development",
  "icon": "🌐",
  "created_at": "2025-11-22T10:00:00.000Z",
  "updated_at": "2025-11-22T10:00:00.000Z",
  "scoped_classes": ["Ghostty"],
  "remote": {
    "enabled": true,
    "host": "hetzner-sway.tailnet",
    "user": "vpittamp",
    "working_dir": "/home/vpittamp/dev/my-app",
    "port": 22
  }
}
```

### Remote Project with Custom Port

```json
{
  "name": "staging-server",
  "directory": "/home/vpittamp/projects/staging",
  "display_name": "Staging Server",
  "icon": "🚀",
  "created_at": "2025-11-22T10:00:00.000Z",
  "updated_at": "2025-11-22T10:00:00.000Z",
  "scoped_classes": ["Ghostty"],
  "remote": {
    "enabled": true,
    "host": "192.168.1.100",
    "user": "deploy",
    "working_dir": "/opt/applications/staging",
    "port": 2222
  }
}
```

## Relationships

```
┌────────────────────────┐
│       Project          │
│────────────────────────│
│ name: string           │
│ directory: string      │
│ display_name: string   │
│ icon: string           │
│ created_at: datetime   │
│ updated_at: datetime   │
│ scoped_classes: list   │
│ remote: ?RemoteConfig  │──┐
└────────────────────────┘  │
                            │ 0..1
                            │
                            ▼
              ┌────────────────────────┐
              │    RemoteConfig        │
              │────────────────────────│
              │ enabled: bool          │
              │ host: string           │
              │ user: string           │
              │ working_dir: string    │
              │ port: int              │
              └────────────────────────┘
```

**Cardinality**: Project has zero or one RemoteConfig (1:0..1)

**Lifecycle**:
1. Project created without `remote` field → Local project
2. Project extended with `remote` field via `set-remote` command → Becomes remote project
3. `remote.enabled` set to `false` → Project exists but operates as local
4. `remote` field removed via `unset-remote` command → Reverts to local project

## State Transitions

```
┌──────────────┐
│ Local Project│
│ (remote=null)│
└──────┬───────┘
       │
       │ i3pm project set-remote
       │
       ▼
┌──────────────────┐
│ Remote Project   │
│ (remote.enabled) │
└──────┬───────────┘
       │
       │ i3pm project unset-remote
       │
       ▼
┌──────────────┐
│ Local Project│
│ (remote=null)│
└──────────────┘
```

**Allowed Transitions**:
- Local → Remote: Add `remote` field with `enabled: true`
- Remote → Local: Remove `remote` field entirely (not just set `enabled: false`)
- Remote → Remote: Update `remote` fields (host, user, working_dir, port)

**Forbidden Transitions**:
- Direct mutation of JSON files (use CLI commands for safety and validation)

## Validation Examples

### Valid Configurations

```python
# Minimal remote config
RemoteConfig(
    enabled=True,
    host="hetzner-sway.tailnet",
    user="vpittamp",
    working_dir="/home/vpittamp/dev/app"
)
# ✅ All required fields present, working_dir is absolute

# Custom port
RemoteConfig(
    enabled=True,
    host="192.168.1.100",
    user="deploy",
    working_dir="/opt/app",
    port=2222
)
# ✅ Non-standard port specified

# Disabled remote (exists but not active)
RemoteConfig(
    enabled=False,
    host="example.com",
    user="user",
    working_dir="/home/user"
)
# ✅ Valid but not used (enabled=False)
```

### Invalid Configurations

```python
# Missing host
RemoteConfig(
    enabled=True,
    user="vpittamp",
    working_dir="/home/vpittamp/dev/app"
)
# ❌ ValidationError: host is required

# Relative working directory
RemoteConfig(
    enabled=True,
    host="hetzner-sway.tailnet",
    user="vpittamp",
    working_dir="relative/path"
)
# ❌ ValidationError: Remote working_dir must be absolute path

# Invalid port
RemoteConfig(
    enabled=True,
    host="hetzner-sway.tailnet",
    user="vpittamp",
    working_dir="/home/vpittamp/dev/app",
    port=100000
)
# ❌ ValidationError: Port must be between 1 and 65535
```

## Migration Path

**Existing Projects**: No migration required
- Existing JSON files without `remote` field remain valid
- Pydantic `Optional[RemoteConfig] = None` default handles missing field
- No changes to existing project behavior

**New Remote Projects**: Created via CLI
```bash
i3pm project create-remote hetzner-dev \
    --local-dir ~/projects/hetzner-dev \
    --remote-host hetzner-sway.tailnet \
    --remote-user vpittamp \
    --remote-dir /home/vpittamp/dev/my-app
```
- CLI validates all fields before writing JSON
- JSON file created with `remote` field populated

**Conversion**: Local → Remote
```bash
i3pm project set-remote existing-project \
    --host hetzner-sway.tailnet \
    --user vpittamp \
    --working-dir /home/vpittamp/dev/app
```
- Reads existing project JSON
- Adds `remote` field with validated configuration
- Preserves all existing fields (name, directory, scoped_classes, etc.)

## Implementation Notes

**Python Module Location**:
- `home-modules/desktop/i3-project-event-daemon/models/project.py` (extend existing `Project` class)
- New file: `home-modules/desktop/i3-project-event-daemon/models/remote_config.py` (new `RemoteConfig` class)
- Update: `home-modules/desktop/i3-project-event-daemon/models/__init__.py` (export `RemoteConfig`)

**TypeScript Module Location**:
- New file: `home-modules/tools/i3pm-cli/src/models/remote-config.ts` (Zod schema + TypeScript interface)
- Update: `home-modules/tools/i3pm-cli/src/models/project.ts` (extend `ProjectSchema` with `remote` field)

**JSON Storage**:
- Location: `~/.config/i3/projects/<name>.json`
- Format: UTF-8 encoded, 2-space indentation
- Permissions: 0644 (user read/write, group/other read)

**Testing Strategy**:
- Unit tests: `tests/087-ssh-projects/unit/test_remote_config_validation.py`
- Validation edge cases: Empty strings, relative paths, invalid ports, missing fields
- Serialization round-trip: JSON → Pydantic → JSON (ensure no data loss)
- Backward compatibility: Load old JSON files without `remote` field
