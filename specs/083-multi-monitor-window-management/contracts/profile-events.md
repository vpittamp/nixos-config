# Contract: Profile Event Protocol

**Feature**: 083-multi-monitor-window-management
**Date**: 2025-11-19

## Overview

Structured events emitted during profile switch operations for observability and debugging.

## Event Format

All profile events use this JSON structure:

```json
{
  "event_type": "profile_switch_start",
  "timestamp": 1700000000.123,
  "profile_name": "dual",
  "previous_profile": "triple",
  "outputs_changed": ["HEADLESS-3"],
  "duration_ms": null,
  "error": null
}
```

## Event Types

### profile_switch_start

Emitted when profile switch is initiated.

**Fields**:
- `profile_name`: Target profile
- `previous_profile`: Current profile (for rollback)
- `outputs_changed`: Outputs that will change state

### output_enable

Emitted when an output is enabled.

**Fields**:
- `profile_name`: Profile being applied
- `outputs_changed`: Single output that was enabled

### output_disable

Emitted when an output is disabled.

**Fields**:
- `profile_name`: Profile being applied
- `outputs_changed`: Single output that was disabled

### workspace_reassign

Emitted when workspaces are redistributed.

**Fields**:
- `profile_name`: Profile being applied
- `duration_ms`: Time taken for reassignment

### profile_switch_complete

Emitted on successful profile switch.

**Fields**:
- `profile_name`: New active profile
- `previous_profile`: Previous profile
- `duration_ms`: Total switch duration
- `outputs_changed`: All outputs that changed

### profile_switch_failed

Emitted on profile switch failure.

**Fields**:
- `profile_name`: Target profile that failed
- `error`: Error message
- `outputs_changed`: Outputs that were partially changed

### profile_switch_rollback

Emitted when rolling back to previous profile.

**Fields**:
- `profile_name`: Previous profile being restored
- `error`: Original error that caused rollback

## Event Sequence

**Successful Switch**:
```
profile_switch_start
  → output_disable (0..N times)
  → output_enable (0..N times)
  → workspace_reassign
  → profile_switch_complete
```

**Failed Switch with Rollback**:
```
profile_switch_start
  → output_disable (0..N times)
  → output_enable (failure)
  → profile_switch_failed
  → profile_switch_rollback
  → output_enable (restore)
  → output_disable (restore)
  → workspace_reassign
```

## Storage

Events stored in EventBuffer (circular, max 500 events).

Query via: `i3pm diagnose events --type profile_switch`

## Success Criteria Verification

- **SC-003**: Count events with duplicate workspace_reassign in same switch
- **SC-004**: Measure duration_ms in profile_switch_complete events
