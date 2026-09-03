---
type: Architecture
title: Modular Flake Architecture
description: Comprehensive overview of the NixOS flake structure utilizing flake-parts, modular outputs, and shared configurations.
status: stable
tags:
  - architecture
  - nixos
  - flake-parts
generated:
  by: okf-curator/gemini-3.8-flash
  at: "2026-09-03T23:25:00Z"
sources:
  - id: flake-nix
    title: Flake Entrypoint
    path: flake.nix
    resource: flake.nix
  - id: configurations-base
    title: Shared Base Configuration
    path: configurations/base.nix
    resource: configurations/base.nix
  - id: nixos-readme
    title: Repository README Documentation
    path: README.md
    resource: README.md
---

# Modular Flake Architecture

The NixOS configuration repository is organized around a clean, modular architecture centered on Nix Flakes and `flake-parts`.[^flake-nix] This architecture unifies disparate workstation and mobile setups while eliminating duplicate configuration logic across devices.

## Core Structure

1. **Flake Entrypoint (`flake.nix`)**:
   Declares pinned inputs including `nixpkgs`, `home-manager`, `nixos-hardware`, and custom tools such as `walker`, `quickshell`, and `herdr`.[^flake-nix] Outputs are partitioned into packages, checks, devshells, and system-level `nixosConfigurations`.

2. **Shared Base Layer (`configurations/base.nix`)**:
   Encapsulates foundational system parameters shared by all hosts, including base substituters/binary caches, common shell utilities, core security primitives, and Nix daemon defaults.[^configurations-base]

3. **Domain Modules (`modules/` and `home-modules/`)**:
   Separates system-level services (networking, desktop display managers, hardware interfaces) from user-scoped environment configurations managed through Home Manager.[^nixos-readme]

## Benefits

- **Hermeticity**: Pinned inputs in `flake.lock` guarantee reproducible builds across workstations.
- **Portability**: Reusable modules can be toggled per device without modifying core definitions.
- **Progressive Composition**: Host declarations compose the shared base with hardware profiles and specialized desktop features.

[^flake-nix]: Flake Entrypoint (flake.nix)
[^configurations-base]: Shared Base Configuration (configurations/base.nix)
[^nixos-readme]: Repository README Documentation (README.md)
