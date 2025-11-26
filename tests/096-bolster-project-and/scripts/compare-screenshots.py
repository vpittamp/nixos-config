#!/usr/bin/env python3
"""
Feature 096: Screenshot comparison utility using PIL

Compares two screenshots and reports if they differ beyond a threshold.
Used for visual regression testing of eww widgets.

Usage:
    compare-screenshots.py baseline.png current.png [--threshold 0.05]

Returns:
    Exit 0 if images match within threshold
    Exit 1 if images differ significantly
    Exit 2 if error (file not found, etc.)
"""

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image, ImageChops
    import math
except ImportError:
    print("Error: PIL not installed. Run: pip install Pillow", file=sys.stderr)
    sys.exit(2)


def calculate_diff_percentage(img1: Image.Image, img2: Image.Image) -> float:
    """
    Calculate the percentage difference between two images.

    Returns a value between 0.0 (identical) and 1.0 (completely different).
    """
    # Ensure both images are same size
    if img1.size != img2.size:
        # Resize current to match baseline for comparison
        img2 = img2.resize(img1.size, Image.Resampling.LANCZOS)

    # Convert to same mode
    img1 = img1.convert('RGB')
    img2 = img2.convert('RGB')

    # Calculate difference
    diff = ImageChops.difference(img1, img2)

    # Calculate RMS (root mean square) difference
    histogram = diff.histogram()

    # Calculate mean squared error
    sum_squares = 0
    for i, count in enumerate(histogram):
        # Each channel contributes
        channel_idx = i % 256
        sum_squares += count * (channel_idx ** 2)

    total_pixels = img1.size[0] * img1.size[1] * 3  # 3 channels
    if total_pixels == 0:
        return 0.0

    mse = sum_squares / total_pixels
    rms = math.sqrt(mse)

    # Normalize to 0-1 range (255 is max difference per pixel per channel)
    return rms / 255.0


def compare_screenshots(baseline_path: Path, current_path: Path, threshold: float = 0.05) -> bool:
    """
    Compare two screenshots.

    Args:
        baseline_path: Path to baseline (expected) image
        current_path: Path to current (actual) image
        threshold: Maximum allowed difference (0.0-1.0)

    Returns:
        True if images match within threshold, False otherwise
    """
    # Load images
    try:
        baseline = Image.open(baseline_path)
    except FileNotFoundError:
        print(f"Error: Baseline image not found: {baseline_path}", file=sys.stderr)
        sys.exit(2)
    except Exception as e:
        print(f"Error loading baseline image: {e}", file=sys.stderr)
        sys.exit(2)

    try:
        current = Image.open(current_path)
    except FileNotFoundError:
        print(f"Error: Current image not found: {current_path}", file=sys.stderr)
        sys.exit(2)
    except Exception as e:
        print(f"Error loading current image: {e}", file=sys.stderr)
        sys.exit(2)

    # Calculate difference
    diff_pct = calculate_diff_percentage(baseline, current)

    # Report results
    match_status = "PASS" if diff_pct <= threshold else "FAIL"
    print(f"Difference: {diff_pct:.4f} ({diff_pct*100:.2f}%)")
    print(f"Threshold:  {threshold:.4f} ({threshold*100:.2f}%)")
    print(f"Result:     {match_status}")

    if diff_pct > threshold:
        # Save diff image for debugging
        diff_path = current_path.with_suffix('.diff.png')
        try:
            diff_img = ImageChops.difference(
                baseline.convert('RGB').resize(current.size, Image.Resampling.LANCZOS),
                current.convert('RGB')
            )
            # Amplify differences for visibility
            diff_img = diff_img.point(lambda x: min(255, x * 10))
            diff_img.save(diff_path)
            print(f"Diff image: {diff_path}")
        except Exception as e:
            print(f"Warning: Could not save diff image: {e}", file=sys.stderr)

        return False

    return True


def main():
    parser = argparse.ArgumentParser(
        description="Compare screenshots for visual regression testing"
    )
    parser.add_argument("baseline", type=Path, help="Path to baseline (expected) image")
    parser.add_argument("current", type=Path, help="Path to current (actual) image")
    parser.add_argument(
        "--threshold", "-t",
        type=float,
        default=0.05,
        help="Maximum allowed difference (0.0-1.0, default: 0.05 = 5%%)"
    )
    parser.add_argument(
        "--quiet", "-q",
        action="store_true",
        help="Only output result code, no text"
    )

    args = parser.parse_args()

    if args.quiet:
        # Suppress output
        sys.stdout = open('/dev/null', 'w')

    if compare_screenshots(args.baseline, args.current, args.threshold):
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
