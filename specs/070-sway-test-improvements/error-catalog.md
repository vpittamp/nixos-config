# Error Message Catalog - Feature 070

**Feature**: Sway Test Framework Usability Improvements
**User Story**: US1 - Clear Error Diagnostics
**Purpose**: Comprehensive catalog of all StructuredError messages with examples

## Error Types Overview

Feature 070 defines 8 error types with structured diagnostic information:

| Error Type | Component | Use Case |
|------------|-----------|----------|
| `APP_NOT_FOUND` | App Registry Reader | Application not found in registry |
| `PWA_NOT_FOUND` | PWA Registry Reader | PWA not found in registry |
| `INVALID_ULID` | PWA Registry Reader | ULID format validation failure |
| `LAUNCH_FAILED` | Action Executor | Application/PWA launch failure |
| `TIMEOUT` | Action Executor | Operation timeout |
| `MALFORMED_TEST` | Test Loader | Invalid test JSON structure |
| `REGISTRY_ERROR` | Registry Loader | Registry file issues |
| `CLEANUP_FAILED` | Cleanup Manager | Cleanup operation failure |

---

## Error Type 1: APP_NOT_FOUND

**Trigger**: Test references application name that doesn't exist in registry

**Example Test Input**:
```json
{
  "type": "launch_app_sync",
  "params": {"app_name": "firefx"}
}
```

**Error Output**:
```
Error: APP_NOT_FOUND - App Registry Reader
Application "firefx" not found in registry

Remediation steps:
  • Did you mean one of these? firefox, firefox-pwa
  • Run: sway-test list-apps --filter firefx
  • Add the app to app-registry-data.nix if it's missing
  • Verify the registry was generated correctly: cat ~/.config/i3/application-registry.json

Diagnostic context:
  - app_name: firefx
  - registry_path: ~/.config/i3/application-registry.json
  - available_apps: [firefox, firefox-pwa, code, alacritty, ... (22 total)]
  - similar_apps: [firefox, firefox-pwa]
  - app_count: 22
```

**Code Location**: `src/services/app-registry-reader.ts:232` (lookupApp function)

---

## Error Type 2: PWA_NOT_FOUND

**Trigger**: Test references PWA name that doesn't exist in registry

**Example Test Input**:
```json
{
  "type": "launch_pwa_sync",
  "params": {"pwa_name": "youtbe"}
}
```

**Error Output**:
```
Error: PWA_NOT_FOUND - PWA Registry Reader
PWA "youtbe" not found in registry

Remediation steps:
  • Check the PWA name spelling (available: youtube, claude, chatgpt, github, notion, linear, slack, calendar, gmail)
  • Add the PWA to pwa-sites.nix if it's missing
  • Verify the registry was generated correctly: cat ~/.config/i3/pwa-registry.json
  • Run pwa-list to see all configured PWAs

Diagnostic context:
  - pwa_name: youtbe
  - registry_path: ~/.config/i3/pwa-registry.json
  - available_pwas: [youtube, claude, chatgpt, github, notion, linear, slack, calendar, gmail]
  - pwa_count: 9
```

**Code Location**: `src/services/app-registry-reader.ts:384` (lookupPWA function)

---

## Error Type 3: INVALID_ULID

**Trigger**: Test provides malformed ULID (not 26 characters or invalid base32 alphabet)

**Example Test Input**:
```json
{
  "type": "launch_pwa_sync",
  "params": {"pwa_ulid": "01K666N2V6BQMDSBMX3"}
}
```

**Error Output**:
```
Error: INVALID_ULID - PWA Registry Reader
Invalid ULID format: "01K666N2V6BQMDSBMX3"

Remediation steps:
  • ULID must be exactly 26 characters long
  • ULID must use base32 alphabet: 0-9, A-Z (excluding I, L, O, U)
  • Example valid ULID: 01ARZ3NDEKTSV4RRFFQ69G5FAV
  • Check PWA registry for correct ULID: cat ~/.config/i3/pwa-registry.json

Diagnostic context:
  - provided_ulid: 01K666N2V6BQMDSBMX3
  - ulid_length: 23
  - expected_length: 26
  - valid_pattern: ^[0123456789ABCDEFGHJKMNPQRSTVWXYZ]{26}$
```

**Code Location**: `src/services/app-registry-reader.ts:420` (lookupPWAByULID function)

**Validation Regex**: `/^[0123456789ABCDEFGHJKMNPQRSTVWXYZ]{26}$/`

---

## Error Type 4: LAUNCH_FAILED

**Trigger**: Application or PWA fails to launch (firefoxpwa not found, command fails, etc.)

**Example Scenario**: firefoxpwa binary missing

**Error Output**:
```
Error: LAUNCH_FAILED - Action Executor
Failed to launch PWA "youtube": firefoxpwa binary not found

Remediation steps:
  • Ensure firefoxpwa package is installed: nix-env -q firefoxpwa
  • Add firefoxpwa-cli to your NixOS configuration packages
  • Verify PATH includes /usr/bin and ~/.nix-profile/bin
  • Test manually: firefoxpwa site launch 01K666N2V6BQMDSBMX3AY74TY7

Diagnostic context:
  - pwa_name: youtube
  - pwa_ulid: 01K666N2V6BQMDSBMX3AY74TY7
  - command: firefoxpwa site launch 01K666N2V6BQMDSBMX3AY74TY7
  - error_type: Deno.errors.NotFound
```

**Code Location**: `src/services/action-executor.ts` (executeLaunchPWASync function)

---

## Error Type 5: TIMEOUT

**Trigger**: Operation exceeds configured timeout (default 5s for PWA launch)

**Example Scenario**: PWA window fails to appear within timeout

**Error Output**:
```
Error: TIMEOUT - Action Executor
PWA launch timed out after 5000ms waiting for window

Remediation steps:
  • Increase timeout parameter in test (default: 5000ms)
  • Check if PWA is installed: firefoxpwa site list | grep youtube
  • Verify PWA appears when launched manually
  • Check Sway logs for window creation events: journalctl -u sway -f

Diagnostic context:
  - pwa_name: youtube
  - timeout_ms: 5000
  - windows_found: 0
  - expected_class: FFPWA-01K666N2V6BQMDSBMX3AY74TY7
```

**Code Location**: `src/services/action-executor.ts` (executeLaunchPWASync function)

---

## Error Type 6: MALFORMED_TEST

**Trigger**: Test JSON file has invalid structure, missing required fields, or type errors

**Example Test Input**:
```json
{
  "name": "Test",
  "actions": [
    {"type": "launch_pwa_sync"}
  ]
}
```

**Error Output**:
```
Error: MALFORMED_TEST - Test Loader
Invalid test structure: actions[0] missing required parameter

Remediation steps:
  • Ensure launch_pwa_sync has either pwa_name or pwa_ulid parameter
  • Check test JSON against schema in src/models/test-case.ts
  • Valid example:
    {
      "type": "launch_pwa_sync",
      "params": {"pwa_name": "youtube"}
    }
  • Run: deno check main.ts to validate types

Diagnostic context:
  - test_file: tests/sway-tests/integration/test_pwa_launch.json
  - validation_errors: ["params: Required"]
  - action_index: 0
```

**Code Location**: `src/models/test-case.ts` (TestCase schema validation)

---

## Error Type 7: REGISTRY_ERROR

**Trigger**: Registry file not found, malformed JSON, or schema validation failure

### Scenario 1: File Not Found

**Error Output**:
```
Error: REGISTRY_ERROR - Registry Loader
Application registry file not found at: /home/user/.config/i3/application-registry.json

Remediation steps:
  • Ensure the registry file exists at ~/.config/i3/application-registry.json
  • Run: mkdir -p ~/.config/i3 && touch ~/.config/i3/application-registry.json
  • Verify Nix configuration generates the registry file correctly

Diagnostic context:
  - registry_path: /home/user/.config/i3/application-registry.json
  - expected_location: ~/.config/i3/application-registry.json
```

### Scenario 2: Schema Validation Failure

**Error Output**:
```
Error: REGISTRY_ERROR - Registry Loader
Invalid application registry format - schema validation failed

Remediation steps:
  • Fix the following validation errors in /home/user/.config/i3/application-registry.json:
    - applications.2.name: String must contain only lowercase alphanumeric and hyphens
    - applications.5.preferred_workspace: Number must be between 1 and 70
  • Verify registry file matches expected JSON schema
  • Check for missing required fields or incorrect data types

Diagnostic context:
  - registry_path: /home/user/.config/i3/application-registry.json
  - validation_errors: [
      "applications.2.name: String must contain only lowercase alphanumeric and hyphens",
      "applications.5.preferred_workspace: Number must be between 1 and 70"
    ]
```

**Code Location**: `src/services/app-registry-reader.ts:71` (loadAppRegistry function)

---

## Error Type 8: CLEANUP_FAILED

**Trigger**: Cleanup operation encounters errors terminating processes or closing windows

**Example Scenario**: Process refuses to terminate

**Error Output**:
```
Error: CLEANUP_FAILED - Cleanup Manager
Failed to terminate process: PID 12345 (firefox)

Remediation steps:
  • Manually kill the process: kill -9 12345
  • Check if process is zombie: ps aux | grep 12345
  • Verify user has permission to send signals to the process
  • Check system logs: journalctl -xe

Diagnostic context:
  - pid: 12345
  - process_name: firefox
  - signal_sent: SIGTERM
  - wait_duration_ms: 5000
  - error_type: Operation not permitted
```

**Code Location**: `src/services/cleanup-manager.ts:44` (cleanup function)

---

## Error Format Structure

All errors follow the StructuredError format defined in `src/models/structured-error.ts`:

```typescript
interface StructuredError extends Error {
  type: ErrorType;              // Enum: APP_NOT_FOUND, PWA_NOT_FOUND, etc.
  component: string;            // Component that raised the error
  cause: string;                // Root cause description
  remediation: string[];        // Actionable steps to fix
  context: Record<string, any>; // Diagnostic information
}
```

### Display Format

Errors are formatted by `ErrorHandler` service (`src/services/error-handler.ts`):

```
Error: {type} - {component}
{cause}

Remediation steps:
  • {remediation[0]}
  • {remediation[1]}
  • ...

Diagnostic context:
  - {context.key1}: {context.value1}
  - {context.key2}: {context.value2}
  - ...
```

---

## Usage for Test Authors

### Triggering Specific Errors (for testing)

```bash
# APP_NOT_FOUND
deno run main.ts run tests/test_app_not_found.json

# PWA_NOT_FOUND
deno run main.ts run tests/test_pwa_not_found.json

# INVALID_ULID
deno run main.ts run tests/test_invalid_ulid.json

# REGISTRY_ERROR (simulate)
mv ~/.config/i3/application-registry.json ~/.config/i3/application-registry.json.bak
deno run main.ts list-apps
mv ~/.config/i3/application-registry.json.bak ~/.config/i3/application-registry.json
```

### Remediation Quick Reference

| Error Type | Most Common Fix |
|------------|-----------------|
| APP_NOT_FOUND | Check spelling, run `sway-test list-apps` |
| PWA_NOT_FOUND | Check spelling, run `sway-test list-pwas` |
| INVALID_ULID | Use 26-char base32 ULID from PWA registry |
| LAUNCH_FAILED | Install firefoxpwa, check app command |
| TIMEOUT | Increase timeout, verify app launches manually |
| MALFORMED_TEST | Fix JSON structure, check schema |
| REGISTRY_ERROR | Rebuild NixOS config, verify registry exists |
| CLEANUP_FAILED | Manually kill processes, check permissions |

---

## Related Files

- **Error Definitions**: `src/models/structured-error.ts`
- **Error Handler**: `src/services/error-handler.ts`
- **Registry Reader**: `src/services/app-registry-reader.ts`
- **Action Executor**: `src/services/action-executor.ts`
- **Cleanup Manager**: `src/services/cleanup-manager.ts`
- **Test Spec**: `specs/070-sway-test-improvements/spec.md` (User Story 1)

---

_Last updated: 2025-11-10 - Feature 070 Phase 9 (T071)_
