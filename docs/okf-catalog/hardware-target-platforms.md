---
type: Platform Targets
title: Hardware Target Platforms
description: Specifications and deployment configurations for supported hardware targets including ThinkPad, Ryzen, Surface, and containers.
status: stable
tags:
  - hardware
  - platforms
  - nixos
generated:
  by: okf-curator/gemini-3.8-flash
  at: "2026-09-03T23:25:00Z"
sources:
  - id: nixos-targets
    title: NixOS Host Target Definitions
    path: nixos/default.nix
    resource: nixos/default.nix
  - id: hardware-specs
    title: Hardware Specifications Directory
    path: hardware/ryzen.nix
    resource: hardware/ryzen.nix
  - id: nixos-readme
    title: Repository README Documentation
    path: README.md
    resource: README.md
---

# Hardware Target Platforms

This repository manages declarative profiles for multiple heterogeneous hardware platforms and containerized runtimes.[^nixos-readme]

## Maintained Hosts

* **ThinkPad Workstation (`configurations/thinkpad.nix`)**:
  Mobile workstation target optimized for battery life, lid switch policies, dual graphics switching, and Sway tiling window management.[^nixos-targets]
* **Ryzen Desktop (`configurations/ryzen.nix`)**:
  High-performance AMD Ryzen workstation configured for compute-heavy workloads, virtualization, multi-monitor Sway desktop, and custom kernel parameters.[^hardware-specs]
* **Surface Devices (`configurations/surface.nix`, `configurations/surface-pro3.nix`)**:
  Touch- and stylus-optimized configurations leveraging `nixos-hardware` Surface kernel modules.[^nixos-targets]
* **Containers & VMs (`packages/`)**:
  Minimal NixOS images intended for lightweight execution under Docker, Podman, and KubeVirt environments.[^nixos-readme]

## Platform Specialization

Each platform definition imports `configurations/base.nix` and overlays platform-specific hardware scans from `hardware/<target>.nix`.[^hardware-specs] This ensures baseline consistency while accommodating specific driver and hardware module requirements.

[^nixos-targets]: NixOS Host Target Definitions (nixos/default.nix)
[^hardware-specs]: Hardware Specifications Directory (hardware/ryzen.nix)
[^nixos-readme]: Repository README Documentation (README.md)
