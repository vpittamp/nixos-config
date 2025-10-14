# Feature 002: KDE Plasma Performance Optimization for KubeVirt VMs

**Status**: Active  
**Priority**: High  
**Related**: Supersedes Feature 001 (Hyprland migration - archived)

## Overview

Optimize KDE Plasma desktop performance for KubeVirt virtual machines accessed via RustDesk remote desktop protocol.

## Problem Statement

KubeVirt VMs running KDE Plasma exhibit poor graphical performance when accessed remotely, particularly:
- Sluggish window operations
- High CPU usage from compositor
- Laggy cursor movement
- Slow screen updates

## Solution Approach

Multi-phased optimization targeting:
1. KDE compositor settings (XRender backend, disable effects)
2. KubeVirt VM resource allocation (dedicated CPUs, IOThreads)
3. Desktop service cleanup (Baloo, Akonadi)
4. RustDesk configuration tuning

## Expected Outcome

2-3x performance improvement in perceived responsiveness without hardware changes.

## Files

- `spec.md` - Feature specification
- `plan.md` - Implementation plan
- `research.md` - Research findings
