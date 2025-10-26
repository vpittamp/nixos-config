"""
Diagnostic Output Models

Data models for diagnostic CLI output, including PWA identification.

Feature 039 - Task T082
"""

from typing import Optional, Dict, Any, List
from dataclasses import dataclass
from datetime import datetime


@dataclass
class WindowIdentityDiagnostic:
    """
    Comprehensive window identity for diagnostic output.

    Feature 039 - T082: PWA Identification in diagnostic output
    """
    window_id: int
    window_class: str
    window_instance: str
    window_title: str

    # Normalized identification
    normalized_class: str
    normalized_instance: str

    # PWA identification (Feature 039 - T082)
    is_pwa: bool
    pwa_type: Optional[str]  # "firefox", "chrome", or None
    pwa_id: Optional[str]  # Unique PWA identifier

    # I3PM environment
    i3pm_project: Optional[str]
    i3pm_app_name: Optional[str]
    i3pm_scope: Optional[str]
    i3pm_target_workspace: Optional[int]

    # Workspace assignment
    current_workspace: int
    assigned_workspace: Optional[int]
    assignment_source: Optional[str]  # "app_handler", "env_var", "registry", "class_match", "fallback"

    # Registry match
    matched_registry_app: Optional[str]
    match_type: Optional[str]  # "exact", "instance", "normalized", etc.

    # Timestamps
    last_focus_time: Optional[datetime]
    creation_time: Optional[datetime]


@dataclass
class PWAConfigGuidance:
    """
    Configuration guidance for PWA setup.

    Feature 039 - T082: Help users configure PWA rules
    """
    window_class: str
    window_instance: str
    window_title: str

    # Detected PWA information
    is_pwa: bool
    pwa_type: Optional[str]
    pwa_id: Optional[str]

    # Configuration recommendations
    recommended_expected_class: str
    recommended_match_strategy: str  # "class" for Firefox, "instance" for Chrome
    config_example: str  # Example configuration snippet

    # Warnings or notes
    notes: List[str]


def format_pwa_diagnostic(identity: WindowIdentityDiagnostic) -> Dict[str, Any]:
    """
    Format PWA information for diagnostic display.

    Feature 039 - T082

    Args:
        identity: Window identity with PWA information

    Returns:
        Formatted dict for Rich table display
    """
    if not identity.is_pwa:
        return {
            "PWA": "No",
            "PWA Type": "N/A",
            "PWA ID": "N/A",
            "Config Strategy": "Use class or instance matching"
        }

    return {
        "PWA": "Yes",
        "PWA Type": identity.pwa_type or "unknown",
        "PWA ID": identity.pwa_id or "unknown",
        "Config Strategy": (
            "Match by class (unique FFPWA-*)" if identity.pwa_type == "firefox"
            else "Match by instance (generic Google-chrome class)" if identity.pwa_type == "chrome"
            else "Unknown"
        )
    }


def generate_pwa_config_guidance(identity: WindowIdentityDiagnostic) -> PWAConfigGuidance:
    """
    Generate configuration guidance for a PWA window.

    Feature 039 - T082

    Args:
        identity: Window identity with PWA information

    Returns:
        Configuration guidance with examples
    """
    notes = []

    if not identity.is_pwa:
        # Not a PWA - provide standard config guidance
        return PWAConfigGuidance(
            window_class=identity.window_class,
            window_instance=identity.window_instance,
            window_title=identity.window_title,
            is_pwa=False,
            pwa_type=None,
            pwa_id=None,
            recommended_expected_class=identity.window_class,
            recommended_match_strategy="class",
            config_example=f'''{{
  "app_name": "my-app",
  "expected_class": "{identity.window_class}",
  "preferred_workspace": 3,
  "scope": "scoped"
}}''',
            notes=["Not a PWA - use standard class matching"]
        )

    # PWA-specific guidance
    if identity.pwa_type == "firefox":
        # Firefox PWA: Use unique class
        notes.append("Firefox PWA detected - class is unique per PWA")
        notes.append(f"Class '{identity.window_class}' uniquely identifies this PWA")

        return PWAConfigGuidance(
            window_class=identity.window_class,
            window_instance=identity.window_instance,
            window_title=identity.window_title,
            is_pwa=True,
            pwa_type="firefox",
            pwa_id=identity.pwa_id,
            recommended_expected_class=identity.window_class,
            recommended_match_strategy="class",
            config_example=f'''{{
  "app_name": "my-firefox-pwa",
  "expected_class": "{identity.window_class}",
  "preferred_workspace": 4,
  "scope": "scoped"
}}''',
            notes=notes
        )

    elif identity.pwa_type == "chrome":
        # Chrome PWA: Use instance field
        notes.append("Chrome PWA detected - class is generic 'Google-chrome'")
        notes.append(f"Use instance '{identity.window_instance}' to identify this PWA")
        notes.append("Instance field is unique per Chrome PWA")

        return PWAConfigGuidance(
            window_class=identity.window_class,
            window_instance=identity.window_instance,
            window_title=identity.window_title,
            is_pwa=True,
            pwa_type="chrome",
            pwa_id=identity.pwa_id,
            recommended_expected_class=identity.window_instance,  # Use instance!
            recommended_match_strategy="instance",
            config_example=f'''{{
  "app_name": "my-chrome-pwa",
  "expected_class": "{identity.window_instance}",
  "preferred_workspace": 5,
  "scope": "scoped",
  "comment": "Chrome PWA - using instance field for matching"
}}''',
            notes=notes
        )

    else:
        # Unknown PWA type
        notes.append("Unknown PWA type - check window properties")

        return PWAConfigGuidance(
            window_class=identity.window_class,
            window_instance=identity.window_instance,
            window_title=identity.window_title,
            is_pwa=True,
            pwa_type="unknown",
            pwa_id=identity.pwa_id,
            recommended_expected_class=identity.window_class,
            recommended_match_strategy="unknown",
            config_example="# Unable to determine PWA configuration",
            notes=notes
        )
