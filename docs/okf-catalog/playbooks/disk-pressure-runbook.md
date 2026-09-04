---
type: Playbook
title: Disk Pressure Runbook
description: Automated guardrails, monitoring timers, and manual cleanup commands for system disk pressure.
resource: /docs/DISK_PRESSURE_RUNBOOK.md
tags: [nixos, storage, runbook, systemd]
status: stable
stale_after: 2027-01-01T00:00:00Z
generated:
  by: okf-curator/v1
  at: "2026-09-04T12:06:26.083Z"
sources:
  - id: disk-doc
    resource: /docs/DISK_PRESSURE_RUNBOOK.md
    title: Disk Pressure Runbook
    last_modified: 2026-03-18T00:00:00Z
---

# Inspection Commands

Primary commands to identify space consumption across root, nix store, and home directories.[^disk-doc]

* Check filesystem capacity: `df -h /`
* Audit root allocations: `disk-nix-roots-audit`

[^disk-doc]: Disk Pressure Runbook
