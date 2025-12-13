# Quickstart: Biometric Authentication for Ryzen Desktop

**Feature**: 116-explore-biometric-authentication
**Status**: Draft
**Date**: 2025-12-13

## Prerequisites

Before starting, you need:

1. **Compatible USB Fingerprint Reader** (not yet purchased)
   - Recommended: Eikon Mini USB Fingerprint Reader (~$25-40)
   - Verify device is listed on [libfprint supported devices](https://fprint.freedesktop.org/supported-devices.html)

2. **NixOS Ryzen Configuration** already deployed
   - Verify with: `hostname` should return "ryzen"

## Hardware Setup

### Step 1: Purchase Fingerprint Reader

Order an Eikon Mini USB fingerprint reader from Amazon or equivalent retailer.

Alternative compatible devices:
- Any AuthenTec sensor (USB ID: 08ff:xxxx)
- ElanTech sensors (USB ID: 04f3:0903 through 04f3:0c6e)
- Goodix MOC sensors (USB ID: 27c6:5840 through 27c6:6a94)

### Step 2: Connect Reader

1. Plug fingerprint reader into USB port (rear panel recommended)
2. Verify detection:
```bash
lsusb | grep -i fingerprint
# Should show something like: AuthenTec, Inc. Fingerprint Sensor
```

## Configuration Setup

### Step 3: Enable Fingerprint in NixOS

The configuration changes are applied via `configurations/ryzen.nix`:

```nix
# Enable fingerprint in bare-metal service
services.bare-metal = {
  enable = true;
  enableFingerprint = true;  # This enables fprintd
  # ... other existing options
};

# PAM integration for fingerprint authentication
security.pam.services = {
  sudo.fprintAuth = true;
  swaylock.fprintAuth = true;
  polkit-1.fprintAuth = true;
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

### Step 4: Apply Configuration

```bash
# Test build first (REQUIRED per Constitution Principle III)
sudo nixos-rebuild dry-build --flake .#ryzen

# If successful, apply
sudo nixos-rebuild switch --flake .#ryzen
```

## Fingerprint Enrollment

### Step 5: Enroll Fingerprints

After configuration is applied:

```bash
# Start enrollment (run as your user, not root)
fprintd-enroll

# Follow prompts to swipe finger multiple times
# Repeat for additional fingers:
fprintd-enroll -f right-index-finger
fprintd-enroll -f left-index-finger
```

**Tip**: Enroll at least 2-3 fingers for reliability.

### Step 6: Verify Enrollment

```bash
# List enrolled fingerprints
fprintd-list vpittamp

# Test verification
fprintd-verify
```

## 1Password Integration

### Step 7: Enable 1Password Biometric Unlock

1. Open 1Password desktop app
2. Click your account name (top-left) > Settings
3. Go to Security tab
4. Enable "Unlock using system authentication service"
5. Lock 1Password (Ctrl+Shift+L)
6. Unlock - you should see a fingerprint icon

## Testing

### Verify sudo Works

```bash
# Run sudo command
sudo echo "Fingerprint works!"
# Should prompt: "Place your finger on the fingerprint reader"
# Scan finger or press Enter to use password
```

### Verify Screen Lock Works

```bash
# Lock screen
swaylock

# Place finger on reader to unlock
# Or press Enter and type password
```

### Verify 1Password Works

1. Lock 1Password
2. Click the fingerprint icon
3. Scan finger
4. Vault should unlock

## Troubleshooting

### Problem: "No devices available" when enrolling

**Solution**: Check if fingerprint reader is detected:
```bash
lsusb | grep -i fingerprint
systemctl status fprintd
```

If not detected, the reader may not be compatible with libfprint.

### Problem: Fingerprint prompt doesn't appear for sudo

**Solution**: Check PAM configuration:
```bash
cat /etc/pam.d/sudo | grep fprint
```

Should show `auth sufficient pam_fprintd.so` line.

### Problem: 1Password doesn't show fingerprint icon

**Solution**:
1. Make sure you're using the non-Snap version of 1Password
2. Verify polkit rule is applied:
```bash
cat /etc/polkit-1/rules.d/*.rules | grep 1password
```
3. Try toggling "Unlock using system authentication" off and on

### Problem: Authentication timeout is too short

**Solution**: The default timeout is usually sufficient. If issues persist, consider enrolling additional fingers or ensuring the reader has stable USB power.

## Key Bindings

No keyboard shortcuts are added by this feature. Authentication is triggered automatically when:

- Running `sudo` commands
- Locking screen with `swaylock`
- Performing privileged actions (polkit prompts)
- Unlocking 1Password

## Daily Usage

Once set up, biometric authentication is seamless:

1. **sudo commands**: Scan finger when prompted, or press Enter for password
2. **Screen lock**: Scan finger on lock screen, or type password
3. **1Password**: Click fingerprint icon or scan finger on unlock prompt
4. **Polkit prompts**: Scan finger or enter password in dialog

## Rollback

If issues occur, disable fingerprint authentication:

```nix
# In configurations/ryzen.nix
services.bare-metal.enableFingerprint = false;
```

Then rebuild:
```bash
sudo nixos-rebuild switch --flake .#ryzen
```

Your password will continue to work for all authentication.
