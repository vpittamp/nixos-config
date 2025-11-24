# API Contract: Project CRUD Operations

**Feature**: 094-enhance-project-tab
**Service**: `project_crud_handler.py`
**Date**: 2025-11-24

## Overview

Python service handling CRUD operations for i3pm projects and worktrees. Reads/writes JSON files at `~/.config/i3/projects/*.json`.

## Methods

### `create_project(config: ProjectConfig) -> dict`
**Purpose**: Create new project JSON file

**Input**: ProjectConfig Pydantic model
**Output**: `{"status": "success", "path": "~/.config/i3/projects/name.json"}`
**Errors**: Validation errors, duplicate name, invalid directory

### `edit_project(name: str, updates: dict) -> dict`
**Purpose**: Update existing project configuration

**Input**: Project name + field updates
**Output**: `{"status": "success", "conflict": false}`
**Conflict Detection**: Compare file mtime before write per spec.md Q2

### `delete_project(name: str) -> dict`
**Purpose**: Remove project JSON file

**Input**: Project name
**Output**: `{"status": "success"}`
**Validation**: Prevent deletion if has active worktrees (FR-P-015)

### `create_worktree(parent: str, branch: str, path: str, config: dict) -> dict`
**Purpose**: Create worktree via `i3pm worktree create` CLI

**Input**: Parent project, branch name, worktree path, display config
**Output**: `{"status": "success", "cli_result": CLIExecutionResult}`
**CLI Command**: `i3pm worktree create {parent} {branch} {path}`
**Error Handling**: Parse stderr, categorize errors per spec.md Q3

### `delete_worktree(name: str) -> dict`
**Purpose**: Delete worktree with Git cleanup

**Input**: Worktree project name
**Output**: `{"status": "success", "git_cleanup": true}`
**Git Command**: Invokes Git worktree removal
