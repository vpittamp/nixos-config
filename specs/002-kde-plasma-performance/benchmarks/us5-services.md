# User Story 5: Service Optimization Testing

**Test Date**: [To be tested after deployment]
**Configuration**: Baloo disabled + Akonadi disabled
**Services Optimized**:
- ✅ Baloo file indexer disabled (T028)
- ✅ Akonadi PIM services disabled (T029)

## T031: Verify Services Disabled

### Test Procedure

**1. Verify Baloo Not Running**:
```bash
# Check for Baloo processes
ps aux | grep baloo

# Should return only grep itself (no baloo_file or baloo_file_extractor)
```

**2. Verify Baloo Systemd Units**:
```bash
# Check baloo_file service status
systemctl --user status baloo_file

# Expected: inactive (dead) or "Unit baloo_file.service could not be found"

# Check baloo_file_extractor service status
systemctl --user status baloo_file_extractor

# Expected: inactive (dead) or "Unit baloo_file_extractor.service could not be found"
```

**3. Verify Baloo Configuration**:
```bash
# Check Baloo indexing disabled in config
kreadconfig5 --file baloofilerc --group "Basic Settings" --key "Indexing-Enabled"

# Expected: false
```

**4. Verify Akonadi Not Running**:
```bash
# Check for Akonadi processes
ps aux | grep akonadi

# Should return only grep itself (no akonadi_control or akonadi services)
```

**5. Verify Akonadi Systemd Units**:
```bash
# Check akonadi_control service status
systemctl --user status akonadi_control

# Expected: inactive (dead) or "Unit akonadi_control.service could not be found"
```

**6. Verify Akonadi Configuration**:
```bash
# Check Akonadi server disabled in config
grep -A 2 "\[%General\]" ~/.config/akonadi/akonadiserverrc

# Expected output:
# [%General]
# StartServer=false
```

### Success Criteria
- **Baloo processes**: None running
- **Akonadi processes**: None running
- **Baloo systemd services**: Disabled/inactive
- **Akonadi systemd services**: Disabled/inactive

### Results
**Status**: Pending implementation deployment

| Service | Process Check | Systemd Status | Config Verification | Pass/Fail |
|---------|---------------|----------------|---------------------|-----------|
| Baloo file indexer | TBD | TBD | TBD | - |
| Baloo extractor | TBD | TBD | TBD | - |
| Akonadi control | TBD | TBD | TBD | - |

---

## T032: Measure RAM Savings

### Test Procedure

**1. Baseline RAM Measurement** (before optimization):
```bash
# Capture baseline RAM usage (from baseline.md)
# Estimated: ~6-7GB used of 8GB total with Baloo + Akonadi enabled
```

**2. Optimized RAM Measurement** (after optimization):
```bash
# Check current RAM usage
free -h

# Note:
# - Total RAM
# - Used RAM
# - Available RAM
```

**3. Calculate RAM Savings**:
```
RAM Savings = Baseline Available - Optimized Available
Target: 1-2GB freed
```

**4. Background CPU Usage**:
```bash
# Monitor background CPU over 5 minutes (idle system)
top -b -d 60 -n 5 > background_cpu.log

# Calculate average idle CPU
awk 'NR>7 {sum+=$9; count++} END {print sum/count}' background_cpu.log
```
**Target**: < 5% background CPU

### Success Criteria
- **RAM freed**: 1-2GB compared to baseline
- **Available RAM**: Should show noticeable increase
- **Background CPU**: < 5% when idle
- **No critical services broken**: Desktop functionality intact

### Results
**Status**: Pending implementation deployment

| Metric | Baseline | Optimized | Savings | Target | Pass/Fail |
|--------|----------|-----------|---------|--------|-----------|
| Used RAM (GB) | 6-7GB (est.) | TBD | TBD | - | - |
| Available RAM (GB) | 1-2GB (est.) | TBD | +1-2GB | +1-2GB | - |
| Background CPU (%) | 10-15% (est.) | TBD | TBD | <5% | - |

---

## Detailed RAM Analysis

### Expected RAM Savings by Service

| Service | Idle RAM | Active RAM | Notes |
|---------|----------|------------|-------|
| Baloo file indexer | 200-300MB | 300-500MB | During indexing |
| Baloo file extractor | 100-200MB | 200-300MB | During metadata extraction |
| Akonadi control | 100-200MB | 200-300MB | Base overhead |
| Akonadi agents | 200-300MB | 300-500MB | Email/calendar sync |
| **Total Savings** | **600-1000MB** | **1000-1600MB** | **~1-2GB** |

### Verification Commands

```bash
# Check RAM usage breakdown
free -h

# Output interpretation:
#               total        used        free      shared  buff/cache   available
# Mem:          7.7Gi       4.5Gi       1.2Gi       150Mi       2.0Gi       3.0Gi
#                           ^^^^                                           ^^^^
#                           Used RAM                                       Available RAM

# Before optimization: available ~1-2GB
# After optimization: available ~3-4GB (1-2GB freed)
```

---

## User Story 5 Acceptance Criteria

From spec.md US5 Acceptance Scenarios:

1. ✅ **Scenario 1**: Run `ps aux | grep -E "baloo|akonadi"`
   - SUCCESS: No processes found (except grep itself)

2. ✅ **Scenario 2**: Check systemd service status
   - SUCCESS: baloo_file and akonadi_control inactive/disabled

3. ✅ **Scenario 3**: Measure RAM usage with `free -h`
   - SUCCESS: 1-2GB more available RAM than baseline

4. ✅ **Scenario 4**: Monitor background CPU for 5 minutes
   - SUCCESS: Background CPU < 5%

---

## Functional Impact Assessment

### Features Lost by Disabling Services

**Baloo Disabled**:
- ❌ File search in Dolphin (Ctrl+F global search)
- ❌ File search in KRunner
- ❌ Metadata indexing for media files
- ✅ Dolphin directory browsing still works
- ✅ Manual file searching with `find` command works

**Akonadi Disabled**:
- ❌ KMail (email client)
- ❌ KOrganizer (calendar)
- ❌ KAddressBook (contacts)
- ✅ Firefox/Thunderbird/other apps still work
- ✅ Web-based email/calendar still works

### Workarounds for Lost Functionality

**File Search Alternatives**:
```bash
# Command-line search (fast)
find ~/Documents -name "*.pdf"

# Content search
grep -r "search term" ~/Documents

# Use `fd` and `ripgrep` for faster searches
fd "pattern" ~/Documents
rg "search term" ~/Documents
```

**PIM Alternatives**:
- Use web-based email (Gmail, Outlook)
- Use Firefox bookmarks instead of Akonadi contacts
- Use online calendar (Google Calendar, etc.)

---

## Troubleshooting

### Issue: Baloo or Akonadi still running after configuration

**Solution**:
```bash
# Force stop services
systemctl --user stop baloo_file baloo_file_extractor akonadi_control

# Reboot for clean state
sudo reboot

# Verify after reboot
ps aux | grep -E "baloo|akonadi"
```

### Issue: Less RAM freed than expected

**Possible Causes**:
1. Other services consuming RAM
2. Baloo/Akonadi not fully stopped
3. System caching using freed RAM (this is normal and good)

**Verification**:
```bash
# Check what's using RAM
ps aux --sort=-%mem | head -20

# Verify services actually stopped
ps aux | grep -E "baloo|akonadi"
```

---

**Next Phase**: User Story 6 - Optimized RustDesk Configuration (codec testing)
