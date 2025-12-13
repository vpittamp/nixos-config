# Data Model: Biometric Authentication for Ryzen Desktop

**Feature**: 116-explore-biometric-authentication
**Date**: 2025-12-13

## Overview

This document describes the configuration model for biometric authentication on the Ryzen desktop. Since this is a NixOS configuration feature (not a traditional software project), the "data model" describes the NixOS module options, configuration entities, and their relationships.

## NixOS Module Structure

### Existing Module: `services.bare-metal`

**Location**: `modules/services/bare-metal.nix`

The `enableFingerprint` option already exists in the bare-metal module. For desktop systems, we need to ensure this option properly configures USB fingerprint readers.

```nix
options.services.bare-metal = {
  enableFingerprint = mkOption {
    type = types.bool;
    default = false;
    description = "Enable fingerprint reader support (fprintd)";
  };
};
```

**Current implementation** (lines 149-159 of bare-metal.nix):
```nix
# ========== FINGERPRINT READER ==========
# Hardware-specific - only on laptops with fingerprint sensors
services.fprintd = mkIf cfg.enableFingerprint {
  enable = true;
};

# PAM configuration for fingerprint auth
security.pam.services = mkIf cfg.enableFingerprint {
  login.fprintAuth = true;
  sudo.fprintAuth = true;
  # Don't enable for greetd - it can cause issues with auto-login
};
```

### Target Configuration: `configurations/ryzen.nix`

**Required Changes**:

1. Enable fingerprint in bare-metal service:
```nix
services.bare-metal = {
  enable = true;
  enableFingerprint = true;  # Add this line
  # ... other options
};
```

2. Add additional PAM services (swaylock, polkit-1):
```nix
# PAM integration for fingerprint authentication
security.pam.services = {
  sudo.fprintAuth = true;
  swaylock.fprintAuth = true;
  polkit-1.fprintAuth = true;
};
```

3. Add polkit rules for enrollment and 1Password:
```nix
security.polkit.extraConfig = lib.mkAfter ''
  // Allow wheel users to enroll fingerprints without password
  polkit.addRule(function(action, subject) {
    if (action.id == "net.reactivated.fprint.device.enroll" &&
        subject.isInGroup("wheel")) {
      return polkit.Result.YES;
    }
  });

  // Allow 1Password CLI to use biometric unlock via polkit
  polkit.addRule(function(action, subject) {
    if (action.id == "com.1password.1Password.unlock" &&
        subject.isInGroup("wheel")) {
      return polkit.Result.AUTH_SELF;
    }
  });
'';
```

## Configuration Entities

### Entity: Fingerprint Template

**Description**: Biometric data stored by fprintd representing an enrolled fingerprint.

| Attribute | Type | Description |
|-----------|------|-------------|
| username | string | User who enrolled the fingerprint |
| finger | enum | Which finger (left-thumb, left-index, etc.) |
| template | binary | Encrypted fingerprint template data |

**Storage**: `/var/lib/fprint/<username>/<finger>.fp`

**Lifecycle**:
- Created by `fprintd-enroll` command
- Verified by `fprintd-verify` command
- Persists across reboots
- Must be re-enrolled if fingerprint reader changes

### Entity: PAM Service Configuration

**Description**: Authentication rules for specific services.

| Attribute | Type | Description |
|-----------|------|-------------|
| service_name | string | PAM service (sudo, swaylock, polkit-1) |
| fprintAuth | boolean | Enable fingerprint authentication |
| order | integer | Authentication method order (password first, then fingerprint) |

**Storage**: Generated at `/etc/pam.d/<service>` by NixOS

**Behavior**:
- When `fprintAuth = true`, PAM prompts for fingerprint OR password
- User can press Enter to skip fingerprint and use password
- Failed fingerprint attempts don't lock out password entry

### Entity: Polkit Rule

**Description**: Authorization rules for system actions.

| Attribute | Type | Description |
|-----------|------|-------------|
| action_id | string | Action being authorized |
| subject_constraint | expression | Who can perform the action |
| result | enum | Authorization result (YES, NO, AUTH_SELF) |

**Storage**: Generated in `/etc/polkit-1/rules.d/` by NixOS

**Rules needed**:
1. `net.reactivated.fprint.device.enroll` - Allow fingerprint enrollment
2. `com.1password.1Password.unlock` - Allow 1Password biometric unlock

## State Transitions

### Fingerprint Enrollment Flow

```
[No Fingerprint Enrolled]
        |
        v
    fprintd-enroll
        |
        v
[Fingerprint Enrolled] <---> [Re-enrollment Required]
        |                         ^
        v                         |
[Authentication Available]        |
        |                         |
        +--- Hardware Changed ----+
```

### Authentication Flow

```
[Service Requests Auth]
        |
        v
[PAM Checks fprintAuth]
        |
        +--- fprintAuth = false ---> [Password Prompt]
        |
        +--- fprintAuth = true
        |
        v
[Fingerprint Prompt] --- Timeout/Skip ---> [Password Prompt]
        |
        +--- Success ---> [Authenticated]
        |
        +--- Failure ---> [Retry or Password]
```

## Validation Rules

### Pre-flight Checks

1. **Hardware Check**: USB fingerprint reader must be detected
   - Verify with: `lsusb | grep -i fingerprint`
   - Or check fprintd: `fprintd-list <username>`

2. **Service Check**: fprintd service must be running
   - Verify with: `systemctl status fprintd`

3. **Enrollment Check**: At least one fingerprint must be enrolled
   - Verify with: `fprintd-list <username>`

### Configuration Validation

| Rule | Validation |
|------|------------|
| fprintd enabled | `services.fprintd.enable == true` |
| PAM services configured | At least one of sudo/swaylock/polkit-1 has fprintAuth |
| User in wheel group | Required for polkit enrollment rule |
| 1Password installed | Required for biometric unlock integration |

## Relationship Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     NixOS Configuration                          │
│                                                                  │
│  ┌─────────────────────┐    ┌──────────────────────────────┐   │
│  │ configurations/     │    │ modules/services/            │   │
│  │ ryzen.nix          │───>│ bare-metal.nix               │   │
│  │                     │    │ - enableFingerprint option   │   │
│  └─────────────────────┘    └──────────────────────────────┘   │
│           │                              │                       │
│           v                              v                       │
│  ┌─────────────────────┐    ┌──────────────────────────────┐   │
│  │ security.pam        │    │ services.fprintd             │   │
│  │ - sudo.fprintAuth   │    │ - enable                     │   │
│  │ - swaylock          │    └──────────────────────────────┘   │
│  │ - polkit-1          │                 │                       │
│  └─────────────────────┘                 v                       │
│           │                    ┌──────────────────────────────┐ │
│           v                    │ Runtime State                │ │
│  ┌─────────────────────┐      │ - /var/lib/fprint/           │ │
│  │ /etc/pam.d/*        │      │ - fprintd.service            │ │
│  └─────────────────────┘      └──────────────────────────────┘ │
│           │                                                      │
│           v                                                      │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ Authentication Flow                                          ││
│  │ User -> PAM -> fprintd -> USB Reader -> Template Match      ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

## Files Modified

| File | Type | Changes |
|------|------|---------|
| `configurations/ryzen.nix` | Modify | Enable fingerprint, add PAM and polkit config |
| `modules/services/bare-metal.nix` | None | Already has fingerprint support |

No new files need to be created. The implementation modifies existing configuration files following established patterns from the ThinkPad configuration.
