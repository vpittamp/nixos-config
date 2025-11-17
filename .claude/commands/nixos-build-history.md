---
description: Analyze NixOS build history patterns, trends, and common issues
---

# NixOS Build History Analysis

You are analyzing the NixOS build history to identify patterns, trends, and potential issues over time.

## Task

Review build history data to provide insights about build success rates, common failures, generation drift, and optimization opportunities.

## Step 1: Load Build History

```bash
# Check if build history exists
if [ -f /var/log/nixos-builds/build-history.json ]; then
  echo "=== Build History Available ==="
  BUILD_COUNT=$(cat /var/log/nixos-builds/build-history.json | jq 'length')
  echo "Total builds tracked: $BUILD_COUNT"

  # Get date range
  FIRST_BUILD=$(cat /var/log/nixos-builds/build-history.json | jq -r '.[0].buildStart // "unknown"')
  LAST_BUILD=$(cat /var/log/nixos-builds/build-history.json | jq -r '.[-1].buildStart // "unknown"')
  echo "Date range: $FIRST_BUILD to $LAST_BUILD"
else
  echo "No build history found at /var/log/nixos-builds/build-history.json"
  echo "Build wrapper hasn't been used yet, or history not enabled"
  echo ""
  echo "Falling back to git history and system generations..."
fi
```

## Step 2: Analyze Build Success Rate

```bash
if [ -f /var/log/nixos-builds/build-history.json ]; then
  echo "=== Build Success Statistics ==="
  cat /var/log/nixos-builds/build-history.json | jq -r '
    (map(select(.success == true)) | length) as $success |
    (map(select(.success == false)) | length) as $failed |
    length as $total |
    "Total builds: \($total)",
    "Successful: \($success) (\($success * 100 / $total | floor)%)",
    "Failed: \($failed) (\($failed * 100 / $total | floor)%)"
  '
fi
```

## Step 3: Identify Failure Patterns

```bash
if [ -f /var/log/nixos-builds/build-history.json ]; then
  echo "=== Failed Builds ==="
  cat /var/log/nixos-builds/build-history.json | jq -r '
    map(select(.success == false)) |
    if length > 0 then
      .[] |
      "Date: \(.buildStart)",
      "Command: \(.command)",
      "Exit Code: \(.exitCode)",
      "Error Preview: \(.errors[:200])...",
      "---"
    else
      "No failed builds recorded"
    end
  '
fi
```

## Step 4: Build Duration Trends

```bash
if [ -f /var/log/nixos-builds/build-history.json ]; then
  echo "=== Build Duration Statistics ==="
  cat /var/log/nixos-builds/build-history.json | jq -r '
    map(.buildDuration) |
    (add / length) as $avg |
    min as $min |
    max as $max |
    "Average duration: \($avg | floor)s (\($avg / 60 | floor)m \($avg % 60 | floor)s)",
    "Fastest build: \($min)s",
    "Slowest build: \($max)s"
  '

  echo ""
  echo "=== Recent Build Times ==="
  cat /var/log/nixos-builds/build-history.json | jq -r '
    .[-10:] | reverse | .[] |
    "\(.buildStart | split("T")[0]) | \(.buildDuration)s | \(if .success then "✓" else "✗" end) | \(.action)"
  '
fi
```

## Step 5: Generation Progression

```bash
if [ -f /var/log/nixos-builds/build-history.json ]; then
  echo "=== Generation History ==="
  cat /var/log/nixos-builds/build-history.json | jq -r '
    map(select(.postGeneration.generation != null)) |
    .[-10:] | .[] |
    "\(.buildStart | split("T")[0]) | \(.preGeneration.generation) → \(.postGeneration.generation) | \(.action)"
  '
else
  # Fallback: use system generations directly
  echo "=== System Generations (last 10) ==="
  ls -lrt /nix/var/nix/profiles/system-*-link 2>/dev/null | tail -10 | awk '{print $6, $7, $8, $9}'
fi
```

## Step 6: Git Commit Analysis

```bash
cd /etc/nixos
echo "=== Recent Git Activity ==="
git log --oneline --since="30 days ago" 2>/dev/null | head -20

echo ""
echo "=== Commits per Day (last 30 days) ==="
git log --since="30 days ago" --format="%ad" --date=short 2>/dev/null | sort | uniq -c | sort -rn | head -10
```

## Step 7: Disk Usage Over Time

```bash
echo "=== Nix Store Growth ==="
df -h /nix/store 2>/dev/null

echo ""
echo "=== Generations vs Storage ==="
GEN_COUNT=$(ls -1d /nix/var/nix/profiles/system-*-link 2>/dev/null | wc -l)
STORE_USED=$(df -h /nix/store 2>/dev/null | tail -1 | awk '{print $3}')
echo "System generations: $GEN_COUNT"
echo "Store usage: $STORE_USED"
echo "Average per generation: ~$(($(df /nix/store 2>/dev/null | tail -1 | awk '{print $3}') / GEN_COUNT / 1024))MB (rough estimate)"
```

## Analysis Output

Based on the data, provide:

### 1. **Build Health Score**

Calculate overall health:
- 90-100% success rate: Excellent
- 75-90%: Good
- 50-75%: Needs attention
- <50%: Critical issues

### 2. **Pattern Recognition**

Identify:
- **Time-based patterns**: Failures clustered at certain times?
- **Action patterns**: Are switches more likely to fail than builds?
- **Duration trends**: Getting slower/faster over time?
- **Generation drift**: How often does generation fall behind?

### 3. **Common Failure Categories**

Group failures by type:
- Syntax errors (configuration mistakes)
- Package build failures (upstream issues)
- Network errors (connectivity problems)
- Disk space issues
- Evaluation timeouts

### 4. **Optimization Recommendations**

Based on patterns:

```
OBSERVATION: Build times increasing (45s → 180s over 2 weeks)
LIKELY CAUSE: More packages/services added without cleanup
RECOMMENDATION:
  1. Run nix-collect-garbage
  2. Consider splitting configuration into profiles
  3. Use binary cache more effectively
```

```
OBSERVATION: Frequent failures on Tuesdays
LIKELY CAUSE: Upstream nixpkgs updates breaking things
RECOMMENDATION:
  1. Pin nixpkgs to specific revision
  2. Test with dry-build before switch
  3. Wait 24h after major nixpkgs updates
```

### 5. **Maintenance Suggestions**

```bash
# If too many generations
sudo nix-collect-garbage --delete-older-than 30d

# If store too large
sudo nix-store --gc

# If builds getting slow
nix flake update  # Get newer, potentially faster builds
```

## Output Format

```
## NixOS Build History Report

**Analysis Period:** [date range]
**Total Builds Analyzed:** [count]
**Health Score:** [score]/100

### Summary Statistics
- Success Rate: [X]%
- Average Build Time: [Y]s
- Total Generations: [Z]

### Trends Identified

**Positive Trends:**
- [List improvements]

**Concerning Patterns:**
- [List issues with recommendations]

### Top Issues

1. **[Issue Category]** (occurred X times)
   - Root cause: [explanation]
   - Fix: [specific steps]

2. **[Issue Category]** (occurred Y times)
   - Root cause: [explanation]
   - Fix: [specific steps]

### Maintenance Recommendations

**Immediate (do now):**
```bash
[commands]
```

**Short-term (this week):**
- [action items]

**Long-term (ongoing):**
- [best practices]

### Build Performance

| Date | Duration | Status | Notes |
|------|----------|--------|-------|
| ... | ... | ... | ... |

### Next Steps
1. [Priority action]
2. [Secondary action]
3. [Ongoing monitoring]
```

## Fallback: No History Available

If build history doesn't exist:

```
## Build History Not Available

The build wrapper hasn't been used yet, so no structured history exists.

### Alternative Analysis

Based on system generations and git history:
- [Analysis of what's available]

### Enable Build Tracking

To start tracking builds:
1. Use nixos-build-wrapper instead of direct nixos-rebuild:
   ```bash
   nixos-build-wrapper os switch
   ```

2. Or use the nh aliases which integrate with the wrapper:
   ```bash
   bash -i -c "nh-m1"
   ```

3. Build history will be stored at:
   - /var/log/nixos-builds/build-history.json (last 100 builds)
   - /var/log/nixos-builds/last-build.json (most recent)
   - /var/log/nixos-builds/last-build.log (full output)

After a few builds, run this command again for full analysis.
```

## When to Use

Invoke this command when:
- Want to understand build patterns over time
- Investigating recurring failures
- Planning system maintenance
- Optimizing build performance
- Before major configuration changes
- Monthly/weekly system health reviews
