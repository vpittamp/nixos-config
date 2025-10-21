"""Unit tests for detection result caching.

Tests the cache file format, timestamp validation, 30-day invalidation,
and cache hit/miss behavior.
"""

import pytest
from unittest.mock import Mock, MagicMock, patch, mock_open
from pathlib import Path
import json
from datetime import datetime, timedelta


class TestCacheFormat:
    """Tests for cache file format (T041, FR-091)."""

    def test_cache_file_location(self):
        """Verify cache file is saved to ~/.cache/i3pm/detected-classes.json.

        FR-091: Cache location in user's cache directory
        """
        try:
            from i3_project_manager.core.app_discovery import get_cache_path
        except ImportError:
            pytest.skip("get_cache_path not yet implemented")

        cache_path = get_cache_path()
        assert str(cache_path).endswith("/.cache/i3pm/detected-classes.json")

    def test_cache_json_structure(self):
        """Verify cache file has required fields: timestamp, cache_version, results.

        FR-091: Cache file format with metadata
        """
        try:
            from i3_project_manager.core.app_discovery import save_detection_cache
        except ImportError:
            pytest.skip("save_detection_cache not yet implemented")

        with patch("builtins.open", mock_open()) as mock_file:
            with patch("pathlib.Path.mkdir"):
                results = {
                    "/usr/share/applications/code.desktop": {
                        "detected_class": "Code",
                        "detection_method": "xvfb",
                        "confidence": 1.0,
                        "timestamp": "2025-01-15T10:30:00",
                    }
                }
                save_detection_cache(results)

                # Get written content
                written_content = "".join(
                    call.args[0] for call in mock_file().write.call_args_list
                )
                cache_data = json.loads(written_content)

                assert "timestamp" in cache_data
                assert "cache_version" in cache_data
                assert "results" in cache_data
                assert cache_data["cache_version"] == "1.0"


class TestCacheInvalidation:
    """Tests for 30-day cache invalidation (T041, FR-091)."""

    def test_cache_valid_when_fresh(self):
        """Verify cache is considered valid when less than 30 days old.

        FR-091: 30-day invalidation period
        """
        try:
            from i3_project_manager.core.app_discovery import is_cache_valid
        except ImportError:
            pytest.skip("is_cache_valid not yet implemented")

        # Cache from 10 days ago
        cache_timestamp = (datetime.now() - timedelta(days=10)).isoformat()

        assert is_cache_valid(cache_timestamp) is True

    def test_cache_invalid_when_old(self):
        """Verify cache is considered invalid when more than 30 days old.

        FR-091: 30-day invalidation period
        """
        try:
            from i3_project_manager.core.app_discovery import is_cache_valid
        except ImportError:
            pytest.skip("is_cache_valid not yet implemented")

        # Cache from 31 days ago
        cache_timestamp = (datetime.now() - timedelta(days=31)).isoformat()

        assert is_cache_valid(cache_timestamp) is False

    def test_cache_invalid_when_corrupted(self):
        """Verify invalid timestamp format is treated as invalid cache.

        FR-091: Robust cache validation
        """
        try:
            from i3_project_manager.core.app_discovery import is_cache_valid
        except ImportError:
            pytest.skip("is_cache_valid not yet implemented")

        assert is_cache_valid("not-a-timestamp") is False
        assert is_cache_valid("") is False

    def test_cache_boundary_at_30_days(self):
        """Verify cache is still valid at exactly 30 days.

        FR-091: 30-day invalidation boundary
        """
        try:
            from i3_project_manager.core.app_discovery import is_cache_valid
        except ImportError:
            pytest.skip("is_cache_valid not yet implemented")

        # Cache from exactly 30 days ago
        cache_timestamp = (datetime.now() - timedelta(days=30)).isoformat()

        # Should still be valid (invalidate AFTER 30 days, not AT 30 days)
        assert is_cache_valid(cache_timestamp) is True


class TestCacheHitMiss:
    """Tests for cache hit/miss behavior (T041, FR-091)."""

    def test_cache_hit_returns_cached_result(self):
        """Verify cache hit returns cached DetectionResult without re-detection.

        FR-091: Use cached results when available
        """
        try:
            from i3_project_manager.core.app_discovery import (
                load_detection_cache,
                get_cached_result,
            )
            from i3_project_manager.models.detection import DetectionResult
        except ImportError:
            pytest.skip("cache functions not yet implemented")

        cache_data = {
            "timestamp": datetime.now().isoformat(),
            "cache_version": "1.0",
            "results": {
                "/usr/share/applications/code.desktop": {
                    "desktop_file": "/usr/share/applications/code.desktop",
                    "app_name": "code",
                    "detected_class": "Code",
                    "detection_method": "xvfb",
                    "confidence": 1.0,
                    "timestamp": "2025-01-15T10:30:00",
                }
            },
        }

        mock_file = mock_open(read_data=json.dumps(cache_data))
        with patch("builtins.open", mock_file):
            with patch("pathlib.Path.exists", return_value=True):
                result = get_cached_result("/usr/share/applications/code.desktop")

        assert result is not None
        assert isinstance(result, DetectionResult)
        assert result.detected_class == "Code"
        assert result.detection_method == "xvfb"

    def test_cache_miss_returns_none(self):
        """Verify cache miss returns None when desktop file not in cache.

        FR-091: Cache miss triggers re-detection
        """
        try:
            from i3_project_manager.core.app_discovery import get_cached_result
        except ImportError:
            pytest.skip("get_cached_result not yet implemented")

        cache_data = {
            "timestamp": datetime.now().isoformat(),
            "cache_version": "1.0",
            "results": {},
        }

        mock_file = mock_open(read_data=json.dumps(cache_data))
        with patch("builtins.open", mock_file):
            with patch("pathlib.Path.exists", return_value=True):
                result = get_cached_result("/usr/share/applications/missing.desktop")

        assert result is None

    def test_expired_cache_returns_none(self):
        """Verify expired cache is treated as cache miss.

        FR-091: Expired cache triggers re-detection
        """
        try:
            from i3_project_manager.core.app_discovery import get_cached_result
        except ImportError:
            pytest.skip("get_cached_result not yet implemented")

        # Cache from 31 days ago
        old_timestamp = (datetime.now() - timedelta(days=31)).isoformat()
        cache_data = {
            "timestamp": old_timestamp,
            "cache_version": "1.0",
            "results": {
                "/usr/share/applications/code.desktop": {
                    "detected_class": "Code",
                    "detection_method": "xvfb",
                    "confidence": 1.0,
                }
            },
        }

        mock_file = mock_open(read_data=json.dumps(cache_data))
        with patch("builtins.open", mock_file):
            with patch("pathlib.Path.exists", return_value=True):
                result = get_cached_result("/usr/share/applications/code.desktop")

        assert result is None

    def test_missing_cache_file_returns_none(self):
        """Verify missing cache file is treated as cache miss.

        FR-091: No cache file triggers initial detection
        """
        try:
            from i3_project_manager.core.app_discovery import get_cached_result
        except ImportError:
            pytest.skip("get_cached_result not yet implemented")

        with patch("pathlib.Path.exists", return_value=False):
            result = get_cached_result("/usr/share/applications/code.desktop")

        assert result is None


class TestCacheUpdate:
    """Tests for cache update after successful detection (T041, FR-091)."""

    def test_successful_detection_updates_cache(self):
        """Verify successful detection result is added to cache.

        FR-091: Update cache after successful detection
        """
        try:
            from i3_project_manager.core.app_discovery import (
                update_cache_with_result,
            )
            from i3_project_manager.models.detection import DetectionResult
        except ImportError:
            pytest.skip("update_cache_with_result not yet implemented")

        result = DetectionResult(
            desktop_file="/usr/share/applications/firefox.desktop",
            app_name="firefox",
            detected_class="Firefox",
            detection_method="xvfb",
            confidence=1.0,
            timestamp=datetime.now().isoformat(),
        )

        # Mock existing cache
        existing_cache = {
            "timestamp": datetime.now().isoformat(),
            "cache_version": "1.0",
            "results": {},
        }

        with patch("builtins.open", mock_open(read_data=json.dumps(existing_cache))) as mock_file:
            with patch("pathlib.Path.exists", return_value=True):
                with patch("pathlib.Path.mkdir"):
                    update_cache_with_result(result)

        # Verify write was called with updated cache
        written_calls = [call for call in mock_file().write.call_args_list]
        assert len(written_calls) > 0

    def test_failed_detection_not_cached(self):
        """Verify failed detection results are not added to cache.

        FR-091: Only cache successful detections
        """
        try:
            from i3_project_manager.core.app_discovery import (
                update_cache_with_result,
            )
            from i3_project_manager.models.detection import DetectionResult
        except ImportError:
            pytest.skip("update_cache_with_result not yet implemented")

        result = DetectionResult(
            desktop_file="/usr/share/applications/broken.desktop",
            app_name="broken",
            detected_class=None,
            detection_method="failed",
            confidence=0.0,
            error_message="Launch failed",
            timestamp=datetime.now().isoformat(),
        )

        with patch("builtins.open", mock_open()) as mock_file:
            with patch("pathlib.Path.exists", return_value=False):
                with patch("pathlib.Path.mkdir"):
                    update_cache_with_result(result)

        # Should NOT write to cache file for failed detection
        # (or write but not include the failed result)
        # Verify by checking that either write wasn't called,
        # or written content doesn't include the failed desktop file

        # For this test, we'll expect no write if cache doesn't exist
        # and result is failed (conservative approach)
        assert mock_file().write.call_count == 0
