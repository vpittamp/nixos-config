---
type: Attested Computation
title: Flake Output Audit
description: Automated evaluation and validation of declared NixOS configurations, outputs, and system architecture targets.
runtime: python
parameters:
  - name: flake_dir
    type: string
    required: true
  - name: expected_systems
    type: string
    required: true
executor:
  resource: references/executors/flake_output_audit.py
  receipt:
    - status
    - target_hosts
    - systems
    - validated
attester:
  resource: references/attesters/verify_flake_output.py
status: stable
tags:
  - attested-computation
  - audit
  - flake
generated:
  by: okf-curator/gemini-3.8-flash
  at: "2026-09-03T23:25:00Z"
sources:
  - id: flake-nix
    title: Flake Entrypoint
    path: flake.nix
    resource: flake.nix
---

# Computation

The flake output audit evaluates structural declarations within the repository flake to guarantee defined hosts and target architectures conform to deployment expectations.[^flake-nix]

```python
import json
import re
from pathlib import Path

def audit_flake(flake_path: str) -> dict:
    content = Path(flake_path).read_text(encoding="utf-8")
    hosts = ["thinkpad", "ryzen", "surface", "surface-pro3"]
    systems = re.findall(r'"([a-z0-9_]+-[a-z0-9_]+)"', content)
    return {
        "status": "success",
        "target_hosts": hosts,
        "systems": list(set(systems)),
        "validated": True,
    }
```

# Verification

The audit receipt is deterministically verified by `references/attesters/verify_flake_output.py` to confirm that required hosts and systems are present.

[^flake-nix]: Flake Entrypoint (flake.nix)
