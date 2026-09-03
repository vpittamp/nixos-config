#!/usr/bin/env python3
"""Attester verifying the flake output audit receipt."""

import json
import sys


def verify_receipt(receipt: dict, expected_systems: list[str]) -> bool:
    if receipt.get("status") != "success":
        return False
    if not receipt.get("validated"):
        return False
    systems = set(receipt.get("systems", []))
    for exp in expected_systems:
        if exp not in systems:
            return False
    return True


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: verify_flake_output.py <receipt-json-path> [expected-systems...]")
        sys.exit(1)
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        receipt_data = json.load(f)
    expected = sys.argv[2:] if len(sys.argv) > 2 else ["x86_64-linux"]
    valid = verify_receipt(receipt_data, expected)
    if valid:
        print("Receipt attestation PASSED")
        sys.exit(0)
    else:
        print("Receipt attestation FAILED")
        sys.exit(1)
