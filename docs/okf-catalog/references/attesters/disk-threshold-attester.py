#!/usr/bin/env python3
"""Deterministic attester for disk pressure checks."""
import json
import sys

def attest(receipt_data):
    threshold = receipt_data.get("threshold", 85)
    reported = receipt_data.get("usage_percent", 0)
    if reported < threshold:
        return {"verdict": "PASS", "message": f"Usage {reported}% is within threshold {threshold}%"}
    return {"verdict": "WARN", "message": f"Usage {reported}% exceeds threshold {threshold}%"}

if __name__ == "__main__":
    receipt = json.loads(sys.stdin.read())
    result = attest(receipt)
    print(json.dumps(result))
    sys.exit(0 if result["verdict"] == "PASS" else 1)
