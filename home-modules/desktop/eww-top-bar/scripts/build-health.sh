#!/usr/bin/env bash
# Produce compact JSON health summary for Eww top bar using nixos-build-status
set -euo pipefail

status_json=$(nixos-build-status --json 2>/dev/null || echo '{}')

python3 - "$status_json" <<'PY'
import json
import sys

try:
    data = json.loads(sys.argv[1])
except Exception:
    print('{"status":"error","os_generation":"--","hm_generation":"--","details":"invalid status json"}')
    sys.exit(0)

gen = data.get("generation", {})
os_gen = gen.get("generation", "--")
hm_gen = gen.get("homeManagerGeneration", "--")

os_out = bool(gen.get("outOfSync", 0))
hm_out = bool(gen.get("homeManagerOutOfSync", 0))
error_count = int(data.get("buildErrors", {}).get("errorCount", 0) or 0)
overall = data.get("overallStatus", "unknown")
can_build = bool(data.get("buildability", {}).get("canBuild", False))
boot_failed = bool(data.get("bootStatus", {}).get("bootFailed", 0))

status = "healthy"
reasons = []
if overall != "success" or error_count > 0 or boot_failed or not can_build:
    status = "error"
elif os_out or hm_out:
    status = "warning"

if error_count:
    reasons.append(f"build errors:{error_count}")
if boot_failed:
    reasons.append("failed units")
if not can_build:
    reasons.append("flake eval failed")
if os_out:
    reasons.append("os out of sync")
if hm_out:
    reasons.append("hm out of sync")
if gen.get("dirty"):
    reasons.append("dirty tree")

detail = "; ".join(reasons) if reasons else "ok"

output = {
    "status": status,
    "os_generation": os_gen,
    "hm_generation": hm_gen,
    "os_out_of_sync": int(os_out),
    "hm_out_of_sync": int(hm_out),
    "error_count": error_count,
    "details": detail,
}
print(json.dumps(output))
PY
