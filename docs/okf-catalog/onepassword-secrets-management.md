---
type: Security Architecture
title: 1Password Secrets Management
description: Centralized, declarative secrets management, SSH agent integration, and Git commit signing via 1Password.
status: stable
tags:
  - security
  - onepassword
  - secrets
generated:
  by: okf-curator/gemini-3.8-flash
  at: "2026-09-03T23:25:00Z"
sources:
  - id: onepass-guide
    title: 1Password Integration Guide
    path: docs/ONEPASSWORD.md
    resource: docs/ONEPASSWORD.md
  - id: onepass-complete
    title: Complete 1Password Integration
    path: docs/1PASSWORD_COMPLETE_INTEGRATION.md
    resource: docs/1PASSWORD_COMPLETE_INTEGRATION.md
---

# 1Password Secrets Management

The repository uses 1Password as the authoritative secrets management and cryptographic identity provider across all hosts.[^onepass-guide]

## Key Features

1. **System & User Separation**:
   - **System Module (`modules/services/onepassword.nix`)**: Installs the 1Password GUI and polkit authentication helpers at the NixOS system layer.[^onepass-guide]
   - **Home Manager Module (`home-modules/tools/onepassword-plugins.nix`)**: Configures user shell plugins, biometric unlock, and environment variables.[^onepass-complete]

2. **SSH Agent Integration**:
   Uses the 1Password SSH agent (`~/.1password/agent.sock`) to authenticate remote connections and sign Git commits without storing unprotected private keys on disk.[^onepass-guide]

3. **Browser Integration**:
   Enables native-host messaging between Chromium/Chrome browsers and the desktop 1Password client through `/run/wrappers/bin/1Password-BrowserSupport`.[^onepass-complete]

## Security Invariants

- No unencrypted secrets or credentials committed to source control.
- Biometric authentication required for accessing hardware keys and secret injection.

[^onepass-guide]: 1Password Integration Guide (docs/ONEPASSWORD.md)
[^onepass-complete]: Complete 1Password Integration (docs/1PASSWORD_COMPLETE_INTEGRATION.md)
