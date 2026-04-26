"""Unit tests for Chrome PWA dynamic app_id matching."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "services"))

from window_identifier import match_pwa_instance, match_with_registry


def test_match_pwa_instance_matches_dynamic_wayland_app_id_with_path_suffix():
    """Chrome PWAs can append path fragments like '__mail' to the dynamic app_id."""
    assert match_pwa_instance(
        "WebApp-01K9WW04PVPHM40D1PV2RVHZFT",
        "chrome-outlook.office.com__mail-Default",
        "",
        pwa_domains=["outlook.office.com", "login.microsoftonline.com"],
    )


def test_match_pwa_instance_matches_domain_aliases():
    """Routing-domain aliases should match dynamic app ids too."""
    assert match_pwa_instance(
        "WebApp-01K666N2V6BQMDSBMX3AY74TY7",
        "chrome-www.youtube.com__-Default",
        "",
        pwa_domains=["youtube.com", "www.youtube.com", "m.youtube.com"],
    )


def test_registry_match_requires_expected_title_when_present():
    registry = {
        "worktree-manager": {
            "display_name": "AI Worktree Manager",
            "expected_class": "quickshell",
            "expected_title_contains": "AI Worktree Manager",
            "preferred_workspace": 23,
        }
    }

    assert (
        match_with_registry(
            actual_class="org.quickshell",
            actual_instance="",
            application_registry=registry,
            window_title="Runtime Settings",
        )
        is None
    )

    match = match_with_registry(
        actual_class="org.quickshell",
        actual_instance="",
        application_registry=registry,
        window_title="AI Worktree Manager",
    )

    assert match is not None
    assert match["_matched_app_name"] == "worktree-manager"
