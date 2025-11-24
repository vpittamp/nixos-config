"""
UI State Data Models

Feature 094: Enhanced Projects & Applications CRUD Interface
Used for real-time form validation, conflict detection, and CLI execution results
"""

from typing import Dict, Optional, Literal
from pydantic import BaseModel, Field


class FormValidationState(BaseModel):
    """
    Real-time form validation state for Eww UI

    Streamed to Eww via deflisten, updated on every keystroke (300ms debounce)
    """
    valid: bool = Field(..., description="True if all fields pass validation")
    errors: Dict[str, str] = Field(default_factory=dict, description="Field name → error message")
    warnings: Dict[str, str] = Field(default_factory=dict, description="Field name → warning message")

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "valid": False,
                    "errors": {
                        "project_name": "Project 'nixos' already exists",
                        "directory": "Directory does not exist: /invalid/path"
                    },
                    "warnings": {}
                },
                {
                    "valid": True,
                    "errors": {},
                    "warnings": {
                        "icon": "Custom icon path not found, will use default"
                    }
                }
            ]
        }
    }


class ConflictResolutionState(BaseModel):
    """
    File modification conflict detection state

    Per spec.md clarification Q2: Detect conflicts via file modification timestamp
    """
    has_conflict: bool = Field(..., description="True if file modified externally")
    file_mtime: float = Field(..., description="File modification timestamp (seconds since epoch)")
    ui_mtime: float = Field(..., description="UI edit start timestamp (seconds since epoch)")
    diff_preview: str = Field(default="", description="Side-by-side diff preview for UI display")

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "has_conflict": True,
                    "file_mtime": 1732468800.0,
                    "ui_mtime": 1732468700.0,
                    "diff_preview": "< file: working_dir = /old/path\n> ui: working_dir = /new/path"
                },
                {
                    "has_conflict": False,
                    "file_mtime": 1732468700.0,
                    "ui_mtime": 1732468700.0,
                    "diff_preview": ""
                }
            ]
        }
    }


class CLIExecutionResult(BaseModel):
    """
    CLI command execution result with error categorization

    Per spec.md clarification Q3: Parse stderr/exit codes for actionable messages
    """
    success: bool = Field(..., description="True if command succeeded (exit code 0)")
    exit_code: int = Field(..., description="Process exit code")
    stdout: str = Field(default="", description="Standard output")
    stderr: str = Field(default="", description="Standard error")
    error_category: Optional[Literal["validation", "permission", "git", "timeout", "unknown"]] = Field(
        default=None, description="Categorized error type for user-friendly messages"
    )
    user_message: str = Field(default="", description="User-friendly error message with recovery steps")
    command: str = Field(..., description="Command that was executed")

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "success": False,
                    "exit_code": 1,
                    "stdout": "",
                    "stderr": "fatal: 'feature-096' is not a commit and a branch 'feature-096' cannot be created from it",
                    "error_category": "git",
                    "user_message": "Branch 'feature-096' not found. Available branches: main, develop, feature-095",
                    "command": "i3pm worktree create nixos feature-096 ~/projects/nixos-feature-096"
                },
                {
                    "success": True,
                    "exit_code": 0,
                    "stdout": "Worktree created successfully",
                    "stderr": "",
                    "error_category": None,
                    "user_message": "",
                    "command": "i3pm worktree create nixos feature-095 ~/projects/nixos-feature-095"
                }
            ]
        }
    }
