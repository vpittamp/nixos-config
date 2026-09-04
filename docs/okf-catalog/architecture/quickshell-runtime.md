---
type: Architecture Specification
title: Quickshell Runtime Shell
description: Architecture for Wayland shell integration, desktop widgets, IPC bridges, and QML state.
resource: /docs/QUICKSHELL_RUNTIME_SHELL.md
tags: [desktop, wayland, quickshell, qml]
status: stable
stale_after: 2027-01-01T00:00:00Z
generated:
  by: okf-curator/v1
  at: "2026-09-04T12:06:26.083Z"
sources:
  - id: quickshell-doc
    resource: /docs/QUICKSHELL_RUNTIME_SHELL.md
    title: Quickshell Runtime Shell Architecture
    last_modified: 2026-08-31T00:00:00Z
---

# Architecture

Quickshell hosts modular QML components communicating with local system daemons over Unix Domain Sockets and D-Bus.[^quickshell-doc]

[^quickshell-doc]: Quickshell Runtime Shell Architecture
