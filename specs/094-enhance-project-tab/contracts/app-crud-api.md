# API Contract: Application CRUD Operations

**Feature**: 094-enhance-project-tab
**Service**: `app_crud_handler.py`
**Date**: 2025-11-24

## Overview

Python service handling CRUD operations for application registry. Edits `home-modules/desktop/app-registry-data.nix` using text-based manipulation per research.md.

## Methods

### `create_application(config: ApplicationConfig) -> dict`
**Purpose**: Add new application to Nix registry

**Input**: ApplicationConfig/PWAConfig Pydantic model
**Output**: `{"status": "success", "ulid": "...", "rebuild_required": true}`
**ULID Generation**: For PWAs, invoke `/etc/nixos/scripts/generate-ulid.sh` per spec.md Q5
**Nix Editing**: Insert mkApp block before `] ++ (builtins.map mkPWAApp pwas)`

### `edit_application(name: str, updates: dict) -> dict`
**Purpose**: Update existing application in Nix registry

**Input**: App name + field updates
**Output**: `{"status": "success", "rebuild_required": true}`
**Nix Editing**: Find mkApp block by name, parse fields, regenerate with updates

### `delete_application(name: str) -> dict`
**Purpose**: Remove application from Nix registry

**Input**: App name
**Output**: `{"status": "success", "pwa_warning": "...", "rebuild_required": true}`
**PWA Warning**: If PWA, return special warning per spec.md FR-A-014

## Rebuild Notification

All methods return `rebuild_required: true`. UI shows notification with:
- "Copy Command" button (copies `sudo nixos-rebuild switch --flake .#<target>`)
- Auto-detect system target: wsl/hetzner-sway/m1
- Instructions: "Run in terminal to apply changes"
