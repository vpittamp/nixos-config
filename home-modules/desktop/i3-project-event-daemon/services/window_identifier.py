"""
Window class identification and normalization service.

Provides tiered window class matching strategy:
1. Exact match (case-sensitive)
2. Instance match (WM_CLASS instance field, case-insensitive)
3. Normalized match (strip reverse-domain prefix, lowercase)

Part of Feature 039 - Tasks T050, T051, T052
"""

import logging
from typing import Tuple, List, Optional

logger = logging.getLogger(__name__)


def normalize_class(class_name: str) -> str:
    """
    Strip reverse-domain prefix and lowercase.

    Examples:
        "com.mitchellh.ghostty" → "ghostty"
        "org.kde.dolphin" → "dolphin"
        "firefox" → "firefox"
        "FFPWA-01234567890" → "ffpwa-01234567890"

    Args:
        class_name: WM_CLASS class field

    Returns:
        Normalized class name (lowercase, without reverse-domain prefix)
    """
    if not class_name:
        return "unknown"

    # Check for reverse-domain notation
    if "." in class_name:
        parts = class_name.split(".")
        # Check if first part is reverse-domain prefix
        if len(parts) > 1 and parts[0].lower() in {
            "com", "org", "io", "net", "dev", "app", "de"
        }:
            class_name = parts[-1]  # Take last component

    return class_name.lower()


def match_window_class(
    expected: str,
    actual_class: str,
    actual_instance: str = "",
    aliases: Optional[List[str]] = None,
) -> Tuple[bool, str]:
    """
    Match window class with tiered fallback strategy and alias support.

    Matching tiers (in order):
    1. Exact match (case-sensitive)
    2. Instance match (WM_CLASS instance field, case-insensitive)
    3. Normalized match (strip reverse-domain prefix, lowercase)

    If aliases are provided, tries matching against each alias using all tiers.

    Args:
        expected: Expected class name (from config/registry)
        actual_class: Actual WM_CLASS class field
        actual_instance: Actual WM_CLASS instance field
        aliases: Optional list of alternative names to match

    Returns:
        (matched, match_type)
        Match types: "exact", "instance", "normalized", "alias_exact",
                     "alias_instance", "alias_normalized", "none"
    """
    # Try matching the expected value directly
    matched, match_type = _match_single(expected, actual_class, actual_instance)
    if matched:
        return (matched, match_type)

    # Try matching against aliases if provided
    if aliases:
        for alias in aliases:
            matched, match_type = _match_single(alias, actual_class, actual_instance)
            if matched:
                # Prefix match type with "alias_"
                return (True, f"alias_{match_type}")

    return (False, "none")


def _match_single(
    expected: str, actual_class: str, actual_instance: str
) -> Tuple[bool, str]:
    """
    Match window class using tiered strategy (internal helper).

    Args:
        expected: Expected class name
        actual_class: Actual WM_CLASS class field
        actual_instance: Actual WM_CLASS instance field

    Returns:
        (matched, match_type)
        Match types: "exact", "instance", "normalized", "none"
    """
    # Tier 1: Exact match (case-sensitive)
    if expected == actual_class:
        return (True, "exact")

    # Tier 2: Instance match (case-insensitive)
    if actual_instance and expected.lower() == actual_instance.lower():
        return (True, "instance")

    # Tier 3: Normalized match
    expected_norm = normalize_class(expected)
    actual_norm = normalize_class(actual_class)
    if expected_norm == actual_norm:
        return (True, "normalized")

    return (False, "none")


def get_window_identity(
    actual_class: str,
    actual_instance: str,
    window_title: Optional[str] = None,
) -> dict:
    """
    Extract comprehensive window identity information.

    Useful for diagnostic output showing all window identification details.

    Implements PWA detection and identification (T079).

    Args:
        actual_class: WM_CLASS class field
        actual_instance: WM_CLASS instance field
        window_title: Window title (optional)

    Returns:
        Dictionary with:
        - original_class: Raw WM_CLASS class field
        - original_instance: Raw WM_CLASS instance field
        - normalized_class: Normalized class name
        - normalized_instance: Normalized instance name
        - title: Window title (if provided)
        - is_pwa: Boolean indicating if window is PWA
        - pwa_id: PWA identifier (if is_pwa=True)
        - pwa_type: Type of PWA ("firefox", "chrome", None)
    """
    identity = {
        "original_class": actual_class,
        "original_instance": actual_instance,
        "normalized_class": normalize_class(actual_class),
        "normalized_instance": normalize_class(actual_instance) if actual_instance else "",
        "title": window_title,
        "is_pwa": False,
        "pwa_id": None,
        "pwa_type": None,
    }

    # Detect PWA (Firefox PWAs use FFPWA-* pattern)
    # Feature 039 - T079: PWA Detection
    if actual_class and actual_class.startswith("FFPWA-"):
        identity["is_pwa"] = True
        identity["pwa_id"] = actual_class  # e.g., FFPWA-01234567890
        identity["pwa_type"] = "firefox"
        logger.debug(f"Detected Firefox PWA: class={actual_class}")

    # Chrome PWAs typically use "Google-chrome" class with specific instance
    # Feature 039 - T079: PWA Detection
    elif actual_class == "Google-chrome" and actual_instance:
        if actual_instance != "google-chrome":  # Not the main Chrome browser
            identity["is_pwa"] = True
            identity["pwa_id"] = actual_instance
            identity["pwa_type"] = "chrome"
            logger.debug(
                f"Detected Chrome PWA: instance={actual_instance}, title={window_title}"
            )

    return identity


def match_pwa_instance(
    pwa_id_expected: str,
    actual_class: str,
    actual_instance: str,
) -> bool:
    """
    Match PWA instance using PWA-specific logic.

    For Chrome PWAs: Matches by instance field (since class is generic "Google-chrome")
    For Firefox PWAs: Matches by class field (since class is unique FFPWA-*)

    Feature 039 - T080: PWA Instance Matching

    Args:
        pwa_id_expected: Expected PWA identifier (from config/registry)
        actual_class: Actual WM_CLASS class field
        actual_instance: Actual WM_CLASS instance field

    Returns:
        True if PWA instance matches, False otherwise

    Examples:
        >>> # Chrome PWA matching
        >>> match_pwa_instance(
        ...     "chat.google.com__work",
        ...     "Google-chrome",
        ...     "chat.google.com__work"
        ... )
        True

        >>> # Firefox PWA matching
        >>> match_pwa_instance(
        ...     "FFPWA-01234567890",
        ...     "FFPWA-01234567890",
        ...     "google-chat"
        ... )
        True
    """
    # Firefox PWA: Match by class (unique per PWA)
    if actual_class and actual_class.startswith("FFPWA-"):
        return pwa_id_expected == actual_class

    # Chrome PWA: Match by instance (class is generic "Google-chrome")
    if actual_class == "Google-chrome" and actual_instance:
        return pwa_id_expected == actual_instance

    # Not a PWA or no match
    return False


def match_with_registry(
    actual_class: str,
    actual_instance: str,
    application_registry: dict,
) -> Optional[dict]:
    """
    Match window against application registry using tiered matching.

    Iterates through all apps in registry, trying to match using tiered strategy.

    Args:
        actual_class: WM_CLASS class field
        actual_instance: WM_CLASS instance field
        application_registry: Application registry dict (app_name -> app_def)

    Returns:
        Matched application definition dict, or None if no match
        Includes additional fields:
        - _match_type: How the match was made (exact/instance/normalized/alias_*)
        - _matched_app_name: Registry app name that matched
    """
    for app_name, app_def in application_registry.items():
        # Get expected class from registry
        expected_class = app_def.get("expected_class", app_name)
        aliases = app_def.get("aliases", [])

        # Try matching
        matched, match_type = match_window_class(
            expected_class, actual_class, actual_instance, aliases
        )

        if matched:
            # Create copy with match metadata
            result = app_def.copy()
            result["_match_type"] = match_type
            result["_matched_app_name"] = app_name
            logger.debug(
                f"Matched window class={actual_class} instance={actual_instance} "
                f"to app={app_name} via {match_type}"
            )
            return result

    logger.debug(
        f"No registry match for class={actual_class} instance={actual_instance}"
    )
    return None
