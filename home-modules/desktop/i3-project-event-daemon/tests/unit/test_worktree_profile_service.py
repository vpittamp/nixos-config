"""Unit tests for worktree host profile service."""

from __future__ import annotations

import json

import pytest

from i3_project_daemon.constants import ConfigPaths
from i3_project_daemon.services.worktree_profile_service import WorktreeProfileService


def test_normalize_host_profile_supports_legacy_aliases() -> None:
    service = WorktreeProfileService(current_user=lambda: "alice")

    profile = service.normalize_host_profile({
        "enabled": "yes",
        "host": "Ryzen",
        "remote_dir": "/home/alice/repo",
        "port": "2222",
    })

    assert profile == {
        "enabled": True,
        "host": "Ryzen",
        "user": "alice",
        "port": 2222,
        "directory": "/home/alice/repo",
    }


def test_validate_host_profile_rejects_missing_or_invalid_fields() -> None:
    service = WorktreeProfileService(current_user=lambda: "alice")

    assert service.validate_host_profile({
        "host": "ryzen",
        "user": "alice",
        "directory": "/srv/repo",
        "port": 22,
    })["directory"] == "/srv/repo"

    with pytest.raises(ValueError, match="directory is required"):
        service.validate_host_profile({"host": "ryzen", "user": "alice"})
    with pytest.raises(ValueError, match="absolute"):
        service.validate_host_profile({"host": "ryzen", "user": "alice", "directory": "relative"})
    with pytest.raises(ValueError, match="port"):
        service.validate_host_profile({"host": "ryzen", "user": "alice", "directory": "/srv/repo", "port": 70000})


def test_save_load_and_get_profiles(tmp_path, monkeypatch) -> None:
    profiles_file = tmp_path / "worktree-host-profiles.json"
    legacy_file = tmp_path / "worktree-remote-profiles.json"
    monkeypatch.setattr(ConfigPaths, "WORKTREE_HOST_PROFILES_FILE", profiles_file)
    monkeypatch.setattr(ConfigPaths, "LEGACY_WORKTREE_REMOTE_PROFILES_FILE", legacy_file)
    service = WorktreeProfileService(current_user=lambda: "alice", timestamp=lambda: 123.0)

    service.save_host_profiles({
        "profiles": {
            "vpittamp/nixos-config:main": {
                "enabled": True,
                "host": "ryzen",
                "user": "alice",
                "port": 22,
                "directory": "/home/alice/nixos-config",
            },
            "vpittamp/nixos-config:off": {
                "enabled": False,
                "host": "ryzen",
                "user": "alice",
                "port": 22,
                "directory": "/home/alice/off",
            },
        },
    })

    loaded = service.load_host_profiles()

    assert loaded["updated_at"] == 123
    assert "vpittamp/nixos-config:main" in loaded["profiles"]
    assert service.get_host_profile("vpittamp/nixos-config:main")["directory"] == "/home/alice/nixos-config"
    assert service.get_host_profile("vpittamp/nixos-config:off") is None
    assert service.get_remote_profile("vpittamp/nixos-config:main")["remote_dir"] == "/home/alice/nixos-config"


def test_load_host_profiles_migrates_legacy_remote_file(tmp_path, monkeypatch) -> None:
    profiles_file = tmp_path / "worktree-host-profiles.json"
    legacy_file = tmp_path / "worktree-remote-profiles.json"
    monkeypatch.setattr(ConfigPaths, "WORKTREE_HOST_PROFILES_FILE", profiles_file)
    monkeypatch.setattr(ConfigPaths, "LEGACY_WORKTREE_REMOTE_PROFILES_FILE", legacy_file)
    legacy_file.write_text(json.dumps({
        "profiles": {
            "vpittamp/nixos-config:main": {
                "enabled": True,
                "host": "ryzen",
                "user": "alice",
                "remote_dir": "/home/alice/nixos-config",
            },
            "ignored": "not-a-profile",
        },
    }))
    service = WorktreeProfileService(current_user=lambda: "alice", timestamp=lambda: 456.0)

    loaded = service.load_host_profiles()

    assert not legacy_file.exists()
    assert profiles_file.exists()
    assert loaded["profiles"]["vpittamp/nixos-config:main"]["directory"] == "/home/alice/nixos-config"
    persisted = json.loads(profiles_file.read_text())
    assert persisted["updated_at"] == 456
    assert persisted["profiles"]["vpittamp/nixos-config:main"]["directory"] == "/home/alice/nixos-config"


def test_remote_profile_validation_returns_legacy_response_shape() -> None:
    service = WorktreeProfileService(current_user=lambda: "alice")

    profile = service.validate_remote_profile({
        "host": "ryzen",
        "user": "alice",
        "remote_dir": "/home/alice/nixos-config",
    })

    assert profile == {
        "enabled": True,
        "host": "ryzen",
        "user": "alice",
        "port": 22,
        "remote_dir": "/home/alice/nixos-config",
    }
