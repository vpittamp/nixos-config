#!/usr/bin/env python3
"""Executor for flake output audit computation."""

import json
import re
import sys
from pathlib import Path


def run_audit(flake_dir: str) -> dict:
    flake_file = Path(flake_dir) / "flake.nix"
    if not flake_file.exists():
        return {
            "status": "error",
            "error": f"flake.nix not found in {flake_dir}",
            "validated": False,
        }

    content = flake_file.read_text(encoding="utf-8")
    systems = re.findall(r'"(x86_64-linux|aarch64-linux|x86_64-darwin|aarch64-darwin)"', content)

    # Inspect nixos targets directory
    nixos_dir = Path(flake_dir) / "configurations"
    target_hosts = []
    if nixos_dir.exists():
        for f in nixos_dir.glob("*.nix"):
            if f.stem not in ("base", "thinkpad-lid-policy"):
                target_hosts.append(f.stem)

    return {
        "status": "success",
        "target_hosts": sorted(target_hosts),
        "systems": sorted(list(set(systems))),
        "validated": True,
    }


if __name__ == "__main__":
    target_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    result = run_audit(target_dir)
    print(json.dumps(result, indent=2))
