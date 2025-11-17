---
description: Perform comprehensive NixOS system health check with AI-assisted analysis
---

# NixOS System Diagnosis

You are performing a comprehensive health check of the NixOS system, analyzing multiple data sources to identify issues and provide actionable recommendations.

## Task

Gather system health data from multiple sources, correlate findings, and provide an intelligent diagnosis with specific remediation steps.

## Step 1: Gather Core Status

Run all diagnostics in parallel for speed:

```bash
# Get structured status data
nixos-build-status --json 2>/dev/null || echo '{"error": "status tool not available"}'
```

```bash
# Check for failed systemd units
systemctl --failed --no-legend 2>/dev/null | head -20
```

```bash
# Get generation sync status
nixos-generation-info 2>/dev/null | head -10
```

```bash
# Check journal for recent errors (last 10 minutes)
journalctl --since "10 min ago" -p err --no-pager 2>/dev/null | head -30
```

## Step 2: Check Build Artifacts (if available)

```bash
# Check for last build log
if [ -f /var/log/nixos-builds/last-build.json ]; then
  echo "=== Last Build Metadata ==="
  cat /var/log/nixos-builds/last-build.json
else
  echo "No build logs found (builds haven't used wrapper yet)"
fi
```

```bash
# Check flake lock freshness
if [ -f /etc/nixos/flake.lock ]; then
  echo "=== Flake Lock Age ==="
  LOCK_MOD=$(stat -c %Y /etc/nixos/flake.lock 2>/dev/null || stat -f %m /etc/nixos/flake.lock 2>/dev/null)
  NOW=$(date +%s)
  AGE_DAYS=$(( (NOW - LOCK_MOD) / 86400 ))
  echo "flake.lock last modified: $AGE_DAYS days ago"

  if [ $AGE_DAYS -gt 30 ]; then
    echo "WARNING: flake.lock is stale (>30 days)"
  fi
fi
```

## Step 3: Check Disk and Memory Pressure

```bash
# Nix store usage
df -h /nix/store 2>/dev/null | tail -1

# Memory pressure
free -h 2>/dev/null | grep Mem
```

```bash
# Count old generations (potential for cleanup)
ls -1d /nix/var/nix/profiles/system-*-link 2>/dev/null | wc -l
```

## Step 4: Analyze and Report

Based on the gathered data, provide:

### 1. **System Health Summary**

Rate overall health: HEALTHY / WARNING / CRITICAL

Criteria:
- HEALTHY: No failed units, generation in sync, no recent errors
- WARNING: 1-2 non-critical issues (stale flake.lock, old generations, high disk usage)
- CRITICAL: Failed units, out-of-sync generation, build errors, critical journal errors

### 2. **Specific Issues Found**

For each issue, provide:
- **What**: Clear description
- **Impact**: How it affects the system
- **Fix**: Exact command(s) to remediate

Example format:
```
ISSUE: 3 failed systemd units
IMPACT: Services not running as expected
FIX:
  systemctl restart sshd
  systemctl reset-failed
```

### 3. **Generation Status Analysis**

- Is current boot generation the latest built?
- Any drift between NixOS and Home Manager generations?
- Commit hash matches flake configuration?

### 4. **Recommendations**

Priority-ordered actionable steps:
1. Critical (must fix now)
2. Important (fix soon)
3. Maintenance (good hygiene)

Examples:
- "Run `sudo nix-collect-garbage -d` - 47 old generations consuming space"
- "Flake inputs stale: `nix flake update` to get security patches"
- "Consider rebuilding: generation out of sync with flake commit"

### 5. **Quick Commands**

Provide copy-paste commands for common fixes:
```bash
# Fix failed units
sudo systemctl reset-failed

# Garbage collect
sudo nix-collect-garbage --delete-older-than 30d

# Rebuild system (pick appropriate target)
bash -i -c "nh-m1"  # or nh-hetzner, nh-wsl
```

## Output Format

Structure your response as:

```
## NixOS System Health Report

**Status: [HEALTHY/WARNING/CRITICAL]**
**Generated: [timestamp]**
**Hostname: [from status]**

### Summary
[2-3 sentence overview]

### Issues Found
[Bulleted list with severity markers]
- CRITICAL: ...
- WARNING: ...
- INFO: ...

### Generation Status
- NixOS: [generation] ([in-sync/out-of-sync])
- Home Manager: [generation]
- Flake Commit: [hash]

### Recommendations
1. [Priority action with command]
2. [Next priority...]

### Quick Fixes
[Code block with commands]
```

## Error Handling

- If `nixos-build-status` not available: Fall back to manual checks
- If `/var/log/nixos-builds/` missing: Note that build tracking isn't configured
- If any command fails: Report what worked and what didn't
- Always provide at least basic systemctl and journal checks

## When to Use

Invoke this command when:
- Before making configuration changes
- After a failed rebuild
- System feels slow or unstable
- Periodic health monitoring
- Before deploying to other machines
