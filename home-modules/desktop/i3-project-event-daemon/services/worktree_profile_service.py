"""Worktree host profile persistence and normalization."""

from __future__ import annotations

import json
import logging
import os
import time
from typing import Any, Callable, Dict, Optional

from ..config import atomic_write_json
from ..constants import ConfigPaths

logger = logging.getLogger(__name__)


class WorktreeProfileService:
    """Own worktree host/remote profile file handling."""

    def __init__(
        self,
        *,
        current_user: Callable[[], str] | None = None,
        timestamp: Callable[[], float] = time.time,
    ) -> None:
        self._current_user = current_user or (lambda: os.environ.get("USER", "vpittamp"))
        self._timestamp = timestamp

    def load_host_profiles(self) -> Dict[str, Any]:
        """Load worktree host profile mapping from disk."""
        default_data: Dict[str, Any] = {
            "version": 1,
            "updated_at": int(self._timestamp()),
            "profiles": {},
        }

        profiles_file = ConfigPaths.WORKTREE_HOST_PROFILES_FILE
        if (
            not profiles_file.exists()
            and ConfigPaths.LEGACY_WORKTREE_REMOTE_PROFILES_FILE.exists()
        ):
            legacy = ConfigPaths.LEGACY_WORKTREE_REMOTE_PROFILES_FILE
            try:
                data = json.loads(legacy.read_text())
                profiles = data.get("profiles", {}) if isinstance(data, dict) else {}
                normalized_profiles = {}
                if isinstance(profiles, dict):
                    for qualified_name, raw_profile in profiles.items():
                        if not isinstance(raw_profile, dict):
                            continue
                        profile = self.normalize_host_profile(raw_profile)
                        if profile.get("host"):
                            normalized_profiles[str(qualified_name)] = profile
                migrated = {
                    "version": 1,
                    "updated_at": int(self._timestamp()),
                    "profiles": normalized_profiles,
                }
                profiles_file.parent.mkdir(parents=True, exist_ok=True)
                atomic_write_json(profiles_file, migrated)
                legacy.unlink(missing_ok=True)
            except Exception as exc:
                logger.warning("[Feature 087] Failed to migrate legacy remote profiles: %s", exc)
        if not profiles_file.exists():
            return default_data

        try:
            data = json.loads(profiles_file.read_text())
            if not isinstance(data, dict):
                return default_data

            profiles = data.get("profiles", {})
            if not isinstance(profiles, dict):
                profiles = {}

            return {
                "version": 1,
                "updated_at": int(data.get("updated_at", int(self._timestamp()))),
                "profiles": profiles,
            }
        except Exception as exc:
            logger.warning("[Feature 087] Failed to read host profiles (using empty map): %s", exc)
            return default_data

    def save_host_profiles(self, data: Dict[str, Any]) -> None:
        """Persist worktree host profile mapping to disk."""
        profiles = data.get("profiles", {})
        if not isinstance(profiles, dict):
            profiles = {}
        to_save = {
            "version": 1,
            "updated_at": int(self._timestamp()),
            "profiles": profiles,
        }
        ConfigPaths.WORKTREE_HOST_PROFILES_FILE.parent.mkdir(parents=True, exist_ok=True)
        atomic_write_json(ConfigPaths.WORKTREE_HOST_PROFILES_FILE, to_save)

    def normalize_host_profile(self, profile: Dict[str, Any]) -> Dict[str, Any]:
        """Normalize host profile payload and support legacy aliases."""
        directory = str(
            profile.get("directory")
            or profile.get("remote_dir")
            or profile.get("working_dir")
            or ""
        ).strip()
        host = str(profile.get("host") or "ryzen").strip()
        user = str(profile.get("user") or self._current_user()).strip()

        enabled_raw = profile.get("enabled", True)
        if isinstance(enabled_raw, str):
            enabled = enabled_raw.strip().lower() in {"1", "true", "yes", "on"}
        else:
            enabled = bool(enabled_raw)

        try:
            port = int(profile.get("port", 22))
        except Exception:
            port = 22

        return {
            "enabled": enabled,
            "host": host,
            "user": user,
            "port": port,
            "directory": directory,
        }

    def validate_host_profile(self, profile: Dict[str, Any]) -> Dict[str, Any]:
        """Validate normalized host profile."""
        normalized = self.normalize_host_profile(profile)

        if not normalized["host"]:
            raise ValueError("host is required")
        if not normalized["user"]:
            raise ValueError("user is required")
        if not normalized["directory"]:
            raise ValueError("directory is required")
        if not normalized["directory"].startswith("/"):
            raise ValueError("directory must be an absolute path")
        if not (1 <= normalized["port"] <= 65535):
            raise ValueError("port must be between 1 and 65535")

        return normalized

    def get_host_profile(self, qualified_name: str) -> Optional[Dict[str, Any]]:
        """Get normalized enabled host profile for a specific worktree."""
        data = self.load_host_profiles()
        raw_profile = data.get("profiles", {}).get(qualified_name)
        if not isinstance(raw_profile, dict):
            return None
        normalized = self.normalize_host_profile(raw_profile)
        if not normalized.get("enabled"):
            return None
        return normalized

    def load_remote_profiles(self) -> Dict[str, Any]:
        """Compatibility alias for legacy worktree remote profile consumers."""
        return self.load_host_profiles()

    def save_remote_profiles(self, data: Dict[str, Any]) -> None:
        """Compatibility alias for legacy worktree remote profile consumers."""
        self.save_host_profiles(data)

    def normalize_remote_profile(self, profile: Dict[str, Any]) -> Dict[str, Any]:
        """Normalize profile into legacy remote_dir response shape."""
        normalized = self.normalize_host_profile(profile)
        return {
            "enabled": normalized["enabled"],
            "host": normalized["host"],
            "user": normalized["user"],
            "port": normalized["port"],
            "remote_dir": normalized["directory"],
        }

    def validate_remote_profile(self, profile: Dict[str, Any]) -> Dict[str, Any]:
        """Validate profile and return legacy remote_dir response shape."""
        normalized = self.validate_host_profile(profile)
        return {
            "enabled": normalized["enabled"],
            "host": normalized["host"],
            "user": normalized["user"],
            "port": normalized["port"],
            "remote_dir": normalized["directory"],
        }

    def get_remote_profile(self, qualified_name: str) -> Optional[Dict[str, Any]]:
        """Get normalized enabled profile in legacy remote_dir response shape."""
        profile = self.get_host_profile(qualified_name)
        if not isinstance(profile, dict):
            return None
        return {
            "enabled": bool(profile.get("enabled", False)),
            "host": str(profile.get("host") or "").strip(),
            "user": str(profile.get("user") or "").strip(),
            "port": int(profile.get("port", 22) or 22),
            "remote_dir": str(profile.get("directory") or "").strip(),
        }
