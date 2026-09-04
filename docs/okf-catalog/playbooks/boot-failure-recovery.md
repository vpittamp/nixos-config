---
type: Playbook
title: Boot Failure Recovery
description: Recovery procedures for Hetzner NixOS boot failures and missing initrd filesystem modules.
resource: /docs/BOOT_FAILURE_RECOVERY.md
tags: [nixos, boot, emergency, hetzner]
status: stable
stale_after: 2027-01-01T00:00:00Z
generated:
  by: okf-curator/v1
  at: "2026-09-04T12:06:26.083Z"
sources:
  - id: boot-guide
    resource: /docs/BOOT_FAILURE_RECOVERY.md
    title: Boot Failure Recovery Guide
    last_modified: 2025-12-12T00:00:00Z
---

# Overview

Triage procedures when Hetzner NixOS fails to mount `/boot` or drops into emergency shell mode.

# Critical Fixes

The `vfat` and codepage modules must be included in `boot.initrd.kernelModules`.[^boot-guide]

[^boot-guide]: Boot Failure Recovery Guide
