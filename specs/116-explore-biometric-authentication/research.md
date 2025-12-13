# Research: Biometric Authentication for Ryzen Desktop

**Feature**: 116-explore-biometric-authentication
**Date**: 2025-12-13

## Executive Summary

This document consolidates research findings for implementing biometric authentication on the AMD Ryzen desktop. The primary recommendation is **USB fingerprint reader authentication** using an Eikon Mini or equivalent libfprint-supported device, which provides a straightforward path to biometric auth with proven NixOS compatibility.

## Hardware Research

### Decision: USB Fingerprint Reader (Eikon Mini)

**Rationale**: The Eikon Mini USB fingerprint reader has native libfprint support, works out of the box on Linux distributions including NixOS, and provides reliable authentication with minimal configuration. It's the most cost-effective and lowest-risk option for desktop biometric authentication.

**Alternatives Considered**:

| Alternative | Why Rejected |
|-------------|--------------|
| Kensington VeriMark | Not supported by libfprint - uses encrypted protocol that hasn't been reverse-engineered |
| YubiKey Bio | Higher cost (~$90 vs ~$30), more complex setup, overkill for single-machine use case |
| Howdy (Facial Recognition) | Not packaged in nixpkgs, requires custom Nix derivation, lower security than fingerprint |
| IR Camera + Howdy | Additional hardware cost + software packaging complexity, not worth the effort |

### Recommended Hardware

**Primary Choice: Eikon Mini USB Fingerprint Reader**
- USB ID: `08ff:2691 AuthenTec, Inc. Fingerprint Sensor`
- Price: ~$25-40 USD
- Linux Support: Native libfprint support (no additional drivers needed)
- Type: Swipe sensor (not touch)
- Tested on: Arch Linux, Ubuntu, NixOS

**Purchase Link**: Available on Amazon (search "Eikon Mini fingerprint reader")

**Alternative Compatible Devices** (from libfprint supported devices list):
- AuthenTec AES1610, AES1660, AES2501, AES2550/AES2810
- ElanTech sensors (04f3:0903 through 04f3:0c6e)
- Goodix MOC sensors (27c6:5840 through 27c6:6a94)
- Synaptics sensors (06cb:00bd through 06cb:01a0)

**IMPORTANT**: Before purchasing any fingerprint reader, verify the USB device ID is listed in the [libfprint supported devices](https://fprint.freedesktop.org/supported-devices.html).

## Software Research

### Decision: fprintd with PAM Integration

**Rationale**: fprintd is the standard fingerprint daemon for Linux, well-supported in NixOS via `services.fprintd.enable`, and already proven working on the ThinkPad configuration in this repository.

**Key Components**:
- **fprintd**: Fingerprint daemon that manages enrollment and verification
- **libfprint**: Low-level library for fingerprint device communication
- **PAM modules**: Integration with system authentication (sudo, swaylock, polkit)

### NixOS Configuration Pattern

The ThinkPad configuration (`configurations/thinkpad.nix:264-303`) provides the reference implementation:

```nix
# Enable fprintd service
services.fprintd.enable = true;

# PAM integration for fingerprint authentication
security.pam.services = {
  sudo.fprintAuth = true;          # Fingerprint for sudo
  swaylock.fprintAuth = true;      # Fingerprint for screen lock
  polkit-1.fprintAuth = true;      # Fingerprint for privilege escalation
  # greetd.fprintAuth = true;      # AVOID - causes display manager issues
};

# Polkit rules for fingerprint enrollment and 1Password
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

### 1Password Integration

**Decision**: Use 1Password's built-in PAM delegation (no special configuration needed)

**How it works**: 1Password desktop app on Linux supports "Unlock using system authentication service" which delegates authentication to PAM. When fingerprint authentication is enabled in PAM, 1Password automatically shows a fingerprint icon and accepts fingerprint scans for vault unlock.

**Setup steps**:
1. Enable fingerprint in NixOS configuration
2. Enroll fingerprint using `fprintd-enroll`
3. In 1Password: Settings > Security > Enable "Unlock using system authentication service"
4. Lock 1Password and reopen - fingerprint icon should appear

**Important**: Must use the non-Snap version of 1Password for fingerprint integration to work.

## USB Fingerprint Reader Considerations

### USB Port Selection

For desktop systems, consider which USB port to use for the fingerprint reader:
- **Front panel USB**: Convenient for daily use, but exposed
- **Rear USB**: More secure but less convenient
- **USB hub**: Can be convenient but may introduce latency

**Recommendation**: Use a dedicated USB 3.0 port on the rear panel for reliability. The fingerprint reader doesn't require USB 3.0 speeds but benefits from stable power delivery.

### Device Persistence

USB devices may change names across reboots. For consistent identification:
- Use `udev` rules if needed (though fprintd typically handles this automatically)
- The fingerprint reader will be auto-detected by fprintd on plug-in

### Power Management

Desktop systems don't have laptop-style USB power management concerns. The reader should remain powered and functional at all times when plugged in.

## Known Issues and Workarounds

### Issue: fprintd blocks password entry in some contexts

**Problem**: When fprintd is enabled, some PAM services may prompt only for fingerprint and not accept password.

**Solution**: NixOS PAM configuration puts password auth before fingerprint auth by default. If issues occur, verify PAM order in `/etc/pam.d/`.

### Issue: Display manager fingerprint login can be unreliable

**Problem**: Enabling `greetd.fprintAuth = true` can cause login issues.

**Solution**: Don't enable fingerprint for display manager login. Use it only for sudo, swaylock, and polkit. This is already the pattern used in the ThinkPad configuration.

### Issue: Multiple fingerprint readers connected

**Problem**: If multiple readers are connected, fprintd may select the wrong one.

**Solution**: Only connect one fingerprint reader. This shouldn't be an issue for typical desktop use.

## YubiKey Bio Research (Alternative)

While not the primary recommendation, YubiKey Bio is a viable alternative for users wanting additional security features.

### Key Features
- On-device fingerprint storage (fingerprints never leave the key)
- FIDO2/U2F support for web authentication
- Portable across machines (no re-enrollment needed)
- PIN fallback after 3 failed attempts

### NixOS Configuration
```nix
# Install pam-u2f
environment.systemPackages = [ pkgs.pam_u2f ];

# PAM configuration for YubiKey
security.pam.services.sudo.u2fAuth = true;
security.pam.services.swaylock.u2fAuth = true;
```

### Enrollment Process
1. Set FIDO2 PIN: `ykman fido access change-pin`
2. Enroll fingerprint: Use Yubico Authenticator app or `ykman fido fingerprints add`
3. Register key with PAM: `pamu2fcfg > ~/.config/Yubico/u2f_keys`

**Not recommended for this feature** due to higher cost and complexity when a simple fingerprint reader meets requirements.

## Facial Recognition Research (Not Recommended)

### Howdy on NixOS

**Status**: Not packaged in nixpkgs (multiple open issues since 2020)

**Issues**:
- [#76928](https://github.com/NixOS/nixpkgs/issues/76928) - Package request (Jan 2020)
- [#230828](https://github.com/NixOS/nixpkgs/issues/230828) - Package request (Sep 2024)
- [#344024](https://github.com/NixOS/nixpkgs/issues/344024) - Latest request

**Would require**:
- Custom Nix derivation for Howdy
- IR camera hardware (~$50-100)
- Custom PAM module configuration
- Ongoing maintenance of the custom package

**Security concerns**:
- Lower security than fingerprint (can be fooled by photos)
- IR camera provides better security but still not as robust as fingerprint
- Howdy saves snapshots that could be used to bypass authentication

**Conclusion**: Not worth the implementation effort for marginal convenience benefit.

## References

- [NixOS Fingerprint Scanner Wiki](https://wiki.nixos.org/wiki/Fingerprint_scanner)
- [NixOS Discourse - fprintd setup guide](https://discourse.nixos.org/t/how-to-use-fingerprint-unlocking-how-to-set-up-fprintd-english/21901)
- [libfprint Supported Devices](https://fprint.freedesktop.org/supported-devices.html)
- [1Password Linux System Authentication](https://support.1password.com/system-authentication-linux/)
- [Howdy GitHub](https://github.com/boltgolt/howdy)
- [YubiKey Bio Series](https://www.yubico.com/products/yubikey-bio-series/)
- [pam-u2f Documentation](https://developers.yubico.com/pam-u2f/)
