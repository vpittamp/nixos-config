---
type: Attested Computation
title: Root Filesystem Pressure Attestation
description: Sanctioned mechanical check confirming root partition disk consumption is within guardrail bounds.
runtime: bash
parameters:
  - { name: threshold, type: integer, required: true }
executor:
  resource: references/skills/check-disk.sh
  receipt: [threshold, usage_percent, status]
attester:
  resource: references/attesters/disk-threshold-attester.py
status: stable
stale_after: 2027-01-01T00:00:00Z
generated:
  by: okf-curator/v1
  at: "2026-09-04T12:06:26.083Z"
sources:
  - id: disk-doc
    resource: /docs/DISK_PRESSURE_RUNBOOK.md
    title: Disk Pressure Runbook
---

# Computation

```bash
df -P / | awk 'NR==2 {print $5}' | tr -d '%'
```

Mechanical verification binds parameter `threshold` without LLM interpolation.[^disk-doc]

[^disk-doc]: Disk Pressure Runbook
