# Feature Specification: Biometric Authentication for Ryzen Desktop

**Feature Branch**: `116-explore-biometric-authentication`
**Created**: 2025-12-13
**Status**: Draft
**Input**: User description: "explore biometric authentication options for our 'ryzen' device which is based on an amd ryzen machine. we already implemented fingerprint authentication on our 'thinkpad' configuration which works great and integrates with 1password which is another requirement. we will purchase hardware such as keys/fingerprint reader, etc. if those are options, or if camera based facial recognition is an option, that would be great. also, consider reviewing the hardware-config repo for nixos to determine if there are configurations for my model machine and to see if there are any solutions we can use."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - USB Fingerprint Reader Authentication (Priority: P1)

As a user of the Ryzen desktop workstation, I want to authenticate using a USB fingerprint reader so that I can unlock my system, authorize sudo commands, and unlock 1Password without typing my password, providing the same experience I have on my ThinkPad.

**Why this priority**: Fingerprint authentication is already proven to work on the ThinkPad configuration, has mature Linux support via fprintd, integrates seamlessly with 1Password via PAM, and requires only purchasing compatible USB hardware. This is the lowest-risk, highest-confidence path to biometric authentication.

**Independent Test**: Can be fully tested by enrolling a fingerprint, locking the screen, and unlocking via fingerprint scan. Success delivers the core value of password-free authentication.

**Acceptance Scenarios**:

1. **Given** a compatible USB fingerprint reader is connected to the Ryzen desktop, **When** the user enrolls their fingerprint using the enrollment process, **Then** the system stores the fingerprint template and confirms successful enrollment.

2. **Given** fingerprints are enrolled and the screen is locked, **When** the user places their finger on the reader, **Then** the screen unlocks within 2 seconds without requiring password entry.

3. **Given** fingerprints are enrolled, **When** the user runs a sudo command in the terminal, **Then** the system prompts for fingerprint OR password authentication, and fingerprint scan authorizes the command.

4. **Given** fingerprints are enrolled and 1Password biometric unlock is enabled, **When** the user opens 1Password, **Then** a fingerprint icon appears and scanning unlocks the vault without requiring the master password.

---

### User Story 2 - YubiKey Bio Hardware Token Authentication (Priority: P2)

As a security-conscious user, I want to use a YubiKey Bio hardware security key for authentication so that I have a portable biometric solution that also provides FIDO2/U2F capabilities for web services and can be used across multiple machines.

**Why this priority**: YubiKey Bio provides biometric authentication with additional security benefits (hardware-bound credentials, FIDO2 support). It requires purchasing specialized hardware (~$90) but offers portability and works across multiple devices without re-enrollment. This is a good secondary option if fingerprint reader proves insufficient or if enhanced security is desired.

**Independent Test**: Can be fully tested by setting up the YubiKey Bio, enrolling fingerprints on the key, and using it for sudo authentication. Success delivers portable biometric auth plus FIDO2 capabilities.

**Acceptance Scenarios**:

1. **Given** a YubiKey Bio is connected to the Ryzen desktop, **When** the user sets up the FIDO2 PIN and enrolls their fingerprint on the YubiKey, **Then** the key stores up to 5 fingerprint templates securely.

2. **Given** fingerprints are enrolled on the YubiKey Bio, **When** the user runs a sudo command, **Then** the system prompts for YubiKey touch with fingerprint verification, and successful biometric match authorizes the command.

3. **Given** the YubiKey Bio is configured, **When** the user accesses a FIDO2-enabled web service (e.g., GitHub, Google), **Then** the user can authenticate using the key's biometric verification.

4. **Given** the YubiKey Bio fails fingerprint verification 3 times, **When** the user attempts to authenticate, **Then** the system falls back to PIN entry for security.

---

### User Story 3 - Facial Recognition Authentication (Priority: P3)

As a user who wants hands-free authentication, I want to use an IR camera for facial recognition so that I can authenticate without physically touching any device, similar to Windows Hello.

**Why this priority**: Facial recognition provides the most convenient hands-free experience but has significant implementation challenges on NixOS: Howdy (the main Linux facial recognition solution) is not packaged in nixpkgs, requires an IR camera for security, and offers lower security than fingerprint authentication. This is an exploratory option requiring more research and custom packaging work.

**Independent Test**: Can be tested by installing Howdy, configuring an IR camera, enrolling face models, and testing sudo authentication. Success delivers hands-free auth but requires significant setup effort.

**Acceptance Scenarios**:

1. **Given** an IR-capable USB camera is connected and Howdy is configured, **When** the user enrolls their face using the enrollment process, **Then** the system stores the face model and confirms successful enrollment.

2. **Given** face enrollment is complete, **When** the user runs a sudo command and looks at the camera, **Then** the system recognizes the face and authorizes the command within 3 seconds.

3. **Given** face enrollment is complete, **When** an unrecognized person attempts to authenticate, **Then** the system rejects the authentication and prompts for password fallback.

4. **Given** lighting conditions are poor, **When** the user attempts facial authentication, **Then** the system gracefully falls back to password authentication.

---

### Edge Cases

- What happens when the USB fingerprint reader is disconnected during authentication? System should gracefully fall back to password authentication.
- What happens when multiple fingerprint readers are connected? System should use the first available reader or allow user selection.
- What happens when fingerprint enrollment data is corrupted? System should provide clear error messages and allow re-enrollment.
- What happens during system sleep/wake cycles? Fingerprint reader should remain functional without re-initialization.
- What happens if 1Password biometric unlock is enabled but no biometric hardware is available? 1Password should gracefully fall back to password entry.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST support at least one biometric authentication method (fingerprint, hardware token, or facial recognition) for the Ryzen desktop.
- **FR-002**: System MUST integrate biometric authentication with PAM for sudo, screen lock (swaylock), and polkit privilege escalation.
- **FR-003**: System MUST integrate biometric authentication with 1Password GUI app unlock via PAM delegation.
- **FR-004**: System MUST provide password fallback when biometric authentication fails or hardware is unavailable.
- **FR-005**: System MUST persist fingerprint enrollment data across reboots.
- **FR-006**: System MUST allow enrolling multiple fingerprints (at least 3) per user.
- **FR-007**: Configuration MUST be implemented as a NixOS module similar to the existing thinkpad.nix fingerprint configuration.
- **FR-008**: Configuration MUST use the existing `services.bare-metal.enableFingerprint` option pattern for consistency.

### Key Entities *(include if feature involves data)*

- **Fingerprint Template**: Biometric data stored by fprintd in `/var/lib/fprint/<username>/`, used to verify fingerprint scans against enrolled prints.
- **PAM Configuration**: Authentication rules in `/etc/pam.d/` that determine which services accept biometric authentication (sudo, swaylock, polkit-1).
- **Hardware Configuration**: NixOS module settings in `configurations/ryzen.nix` that enable/configure biometric services.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can complete fingerprint-based screen unlock in under 2 seconds from first touch.
- **SC-002**: Users can complete fingerprint-based sudo authorization in under 3 seconds from command execution.
- **SC-003**: 1Password biometric unlock works on first attempt for 95%+ of authentication attempts.
- **SC-004**: System falls back to password authentication within 5 seconds when biometric hardware is disconnected.
- **SC-005**: Enrolled fingerprints persist across system reboots with 100% reliability.
- **SC-006**: Configuration can be applied to Ryzen desktop using existing `nixos-rebuild switch` workflow with no manual post-installation steps.

## Research Findings *(informational)*

### Existing ThinkPad Implementation

The thinkpad.nix configuration (`configurations/thinkpad.nix:264-303`) provides a working reference implementation:

- Uses `services.fprintd.enable = true` for the fprintd service
- Configures PAM services: `sudo.fprintAuth`, `swaylock.fprintAuth`, `polkit-1.fprintAuth`
- Adds polkit rules for fingerprint enrollment without password
- Adds polkit rules for 1Password biometric unlock via polkit
- Note: `greetd.fprintAuth` is commented out as it can cause display manager issues

### Hardware Options Research

| Option | Linux Support | Purchase Required | 1Password Compatible | Security Level |
|--------|--------------|-------------------|---------------------|----------------|
| USB Fingerprint Reader (Eikon Mini) | Excellent (libfprint native) | ~$25-40 | Yes (via PAM) | High |
| USB Fingerprint Reader (Goodix/Elan MOC) | Good (libfprint TOD drivers) | Varies | Yes (via PAM) | High |
| YubiKey Bio | Excellent (pam-u2f) | ~$90 | Yes (via PAM) | Very High |
| Kensington VeriMark | Not Supported | N/A | N/A | N/A |
| IR Camera + Howdy | Limited (not in nixpkgs) | ~$50-100 | Unknown | Medium |

### Recommended Hardware

1. **Primary Recommendation**: Eikon Mini USB fingerprint reader - proven Linux compatibility, native libfprint support, works out of the box on Arch/Ubuntu/NixOS.

2. **Alternative**: YubiKey Bio Series (FIDO Edition) - adds FIDO2/U2F support, portable across devices, but higher cost.

3. **Not Recommended**: Kensington VeriMark (not supported by libfprint), Howdy facial recognition (requires custom NixOS packaging, not in nixpkgs).

### NixOS Hardware Repository

The nixos-hardware repository provides AMD Ryzen optimizations but no biometric-specific modules:

- `common-cpu-amd` - Already used in ryzen.nix
- `common-cpu-amd-pstate` - Already used in ryzen.nix
- `common-cpu-amd-zenpower` - Already used in ryzen.nix
- `gigabyte-b550`, `gigabyte-b650` - Motherboard-specific modules available

No biometric hardware profiles exist in nixos-hardware; biometric configuration is handled through standard NixOS services.

## Assumptions

- User will purchase compatible USB fingerprint reader hardware (recommended: Eikon Mini or equivalent libfprint-supported device).
- The existing bare-metal.nix module pattern will be extended for fingerprint support on desktop.
- fprintd enrollment will be done manually via `fprintd-enroll` command after hardware is connected.
- 1Password biometric unlock relies on PAM integration (same as ThinkPad) - no 1Password-specific configuration needed.
- Facial recognition (Howdy) is out of scope for initial implementation due to NixOS packaging complexity; can be added as future enhancement.

## Out of Scope

- Facial recognition via Howdy (requires custom NixOS packaging not in nixpkgs)
- Windows Hello compatibility/integration
- Remote/network biometric authentication
- Biometric data backup/restore across machines
- Multi-user biometric enrollment management
- Display manager (greetd) fingerprint authentication (known to cause issues)
