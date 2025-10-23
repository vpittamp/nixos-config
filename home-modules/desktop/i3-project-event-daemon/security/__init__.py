"""
Security module for i3pm production readiness

This module provides authentication and sanitization functionality
for secure IPC communication and data handling.

Feature 030: Production Readiness
Tasks T009-T010: Security infrastructure
"""

from .auth import authenticate_client, AuthenticationError
from .sanitize import sanitize_text, sanitize_window_title, sanitize_command_line

__all__ = [
    "authenticate_client",
    "AuthenticationError",
    "sanitize_text",
    "sanitize_window_title",
    "sanitize_command_line",
]
