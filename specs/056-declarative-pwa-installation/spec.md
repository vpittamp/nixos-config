# Feature Specification: Declarative PWA Installation

**Feature Branch**: `056-declarative-pwa-installation`
**Created**: 2025-11-02
**Status**: Draft
**Input**: User description: "Fully implement declarative PWA installation approach"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Zero-Touch PWA Deployment (Priority: P1)

As a system administrator deploying NixOS configurations across multiple machines, I want Progressive Web Apps to be automatically installed from a declarative configuration so that I don't need to manually install each PWA through the Firefox GUI on every machine.

**Why this priority**: This is the core value proposition of the feature - eliminating manual installation steps during system deployment. Without this, the feature provides no benefit over the current manual approach.

**Independent Test**: Can be fully tested by defining one PWA in the configuration, rebuilding the system, and verifying the PWA appears installed without any manual Firefox GUI interaction. Delivers immediate value by saving time during deployment.

**Acceptance Scenarios**:

1. **Given** a NixOS configuration with PWA definitions in app-registry, **When** the system is rebuilt, **Then** all defined PWAs appear in the firefoxpwa profile list without manual installation
2. **Given** a fresh NixOS installation on a new machine, **When** the configuration is deployed, **Then** all PWAs are installed and ready to launch
3. **Given** an existing machine with manual PWA installations, **When** switching to declarative configuration, **Then** existing PWAs are preserved and new ones are added

---

### User Story 2 - Cross-Machine Configuration Portability (Priority: P2)

As a user with multiple NixOS machines (e.g., desktop and laptop), I want my PWA configuration to work identically across all machines so that I don't need to track different PWA IDs or update configuration files for each deployment target.

**Why this priority**: Ensures the declarative approach is truly portable and doesn't require machine-specific customization. This is critical for the "declare once, use everywhere" value proposition.

**Independent Test**: Can be tested by deploying the same configuration to two different machines and verifying that PWAs work identically without configuration changes. Delivers value by eliminating machine-specific customization.

**Acceptance Scenarios**:

1. **Given** a PWA configuration on machine A, **When** deployed to machine B, **Then** PWAs install and launch correctly without modifying ULID identifiers or manifest URLs
2. **Given** PWA profile IDs differ between machines, **When** launching a PWA by name, **Then** the system resolves the correct profile ID dynamically
3. **Given** machine-specific file paths in icons or manifests, **When** deploying to different machines, **Then** paths resolve correctly based on the target environment

---

### User Story 3 - Single Source of Truth for PWA Metadata (Priority: P3)

As a configuration maintainer, I want to define PWA metadata (name, URL, workspace assignment, icon) in a single location so that I don't need to duplicate this information across multiple configuration files.

**Why this priority**: Reduces maintenance burden and prevents configuration drift. Important for long-term maintainability but not essential for initial deployment.

**Independent Test**: Can be tested by modifying PWA metadata in the app-registry and verifying the change propagates to all dependent configuration files (home-manager, manifest files, desktop entries). Delivers value by simplifying configuration updates.

**Acceptance Scenarios**:

1. **Given** PWA metadata in app-registry-data.nix, **When** generating home-manager configuration, **Then** PWA names, URLs, and icons are extracted from the registry
2. **Given** a workspace assignment change in app-registry, **When** rebuilding, **Then** the PWA launches on the updated workspace without additional configuration changes
3. **Given** PWA metadata in app-registry, **When** generating manifest files, **Then** manifest JSON reflects the registry data

---

### Edge Cases

- What happens when a PWA is defined in configuration but firefoxpwa fails to install it due to network issues?
- How does the system handle PWA ULID collisions if two machines independently generate the same identifier?
- What happens if a user manually uninstalls a declaratively-configured PWA through Firefox?
- How does the system handle PWAs that require authentication before they can be used?
- What happens when manifest URLs become unavailable or return errors during installation?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST generate valid ULID identifiers for PWA profiles and sites according to the ULID specification (26 characters from alphabet 0-9, A-Z excluding I, L, O, U)
- **FR-002**: System MUST generate Web App Manifest JSON files for each PWA defined in app-registry-data.nix
- **FR-003**: System MUST write firefoxpwa configuration to `~/.local/share/firefoxpwa/config.json` with declaratively-defined ULIDs and manifest URLs
- **FR-004**: System MUST host manifest files at accessible URLs during PWA installation (via HTTP server or file:// protocol)
- **FR-005**: System MUST create desktop entry files for PWAs to enable launcher integration
- **FR-006**: System MUST use home-manager's `programs.firefoxpwa` module for declarative configuration
- **FR-007**: System MUST extract PWA metadata (name, URL, description, icon, workspace) from existing app-registry-data.nix
- **FR-008**: System MUST generate unique ULIDs for each PWA site and store them in a persistent mapping file
- **FR-009**: System MUST support idempotent installation - running the configuration multiple times produces the same result
- **FR-010**: System MUST preserve manually-installed PWAs when declarative configuration is enabled
- **FR-011**: System MUST handle PWA authentication requirements by documenting that users need to log in manually after installation
- **FR-012**: System MUST validate ULID format before writing to config.json
- **FR-013**: System MUST generate manifest files with correct scope, start_url, icons, and display properties
- **FR-014**: System MUST create symlinks for PWA desktop files in `~/.local/share/applications/` for launcher visibility

### Key Entities

- **PWA Definition**: Configuration entry in app-registry-data.nix containing name, URL, description, icon path, workspace assignment, and scope (scoped/global)
- **ULID Identifier**: 26-character unique identifier following ULID specification, used to reference PWA sites and profiles in firefoxpwa configuration
- **Manifest File**: Web App Manifest JSON containing metadata required by firefoxpwa for PWA installation (start_url, scope, name, icons, display mode)
- **ULID Mapping**: Persistent association between PWA names (from app-registry) and their generated ULIDs, stored to ensure consistency across rebuilds

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can deploy PWA configuration to a fresh machine and have all PWAs ready to launch within 5 minutes of system rebuild completion, without manual Firefox GUI interaction
- **SC-002**: Zero configuration changes required when deploying the same PWA definitions to different machines (full cross-machine portability)
- **SC-003**: PWA metadata changes in app-registry propagate to all dependent files (home-manager config, manifests, desktop entries) with a single rebuild
- **SC-004**: 100% of PWAs defined in app-registry are successfully installed and launchable after declarative configuration is applied
- **SC-005**: Users manually authenticate to PWAs once after installation, and authentication persists across system rebuilds
- **SC-006**: Configuration maintains consistency - running rebuild multiple times produces identical results without duplicating PWAs or changing ULIDs

## Scope *(mandatory)*

### In Scope

- Generating ULID identifiers for PWA sites declaratively
- Creating Web App Manifest JSON files from app-registry metadata
- Configuring home-manager's `programs.firefoxpwa` module with generated ULIDs and manifests
- Hosting manifest files for firefoxpwa installation
- Creating desktop entry symlinks for launcher integration
- Documenting manual authentication requirements after PWA installation
- Supporting cross-machine deployment without configuration changes

### Out of Scope

- Automating user authentication to PWAs (requires manual login after installation)
- Migrating existing manually-installed PWAs to declarative configuration (preserved but not managed)
- Supporting PWAs that cannot be installed without native manifests (no changes to browser extension behavior)
- Implementing PWA name lookup in daemon to eliminate hardcoded IDs (separate future enhancement)

## Assumptions *(optional)*

- Users have firefoxpwa and home-manager already installed
- app-registry-data.nix exists and contains PWA definitions with URLs and metadata
- PWAs defined in app-registry have valid URLs that can be accessed
- Users accept that authentication must be performed manually after PWA installation
- The default firefoxpwa profile (00000000000000000000000000) will be used for all PWAs
- Icons referenced in app-registry exist at the specified paths
- System has network access during rebuild for any remote resources needed by manifests

## Dependencies *(optional)*

- **External**: firefoxpwa package (already installed)
- **External**: home-manager with programs.firefoxpwa module support
- **Internal**: app-registry-data.nix for PWA metadata
- **Internal**: pwa-sites.nix for single source of truth about PWA URLs and descriptions
- **Internal**: Existing 1Password declarative integration (remains unchanged)
- **Internal**: Existing dynamic PWA launcher (launch-pwa-by-name) for cross-machine compatibility

## Constraints *(optional)*

- ULID identifiers must conform to specification (26 chars, specific alphabet)
- Manifest files must be accessible via HTTP or file:// URLs during installation
- Cannot automate user authentication due to security/session management requirements
- Must maintain compatibility with existing manual PWA installation workflow
- Configuration must support both fresh installations and systems with existing PWAs
- Must not break existing PWA functionality during migration to declarative approach

## Testing Strategy *(mandatory)*

### Test-Driven Development Approach

This feature MUST be implemented using Test-Driven Development (TDD) methodology:

1. **Write Test First**: For each functional requirement, write failing tests BEFORE implementation
2. **Red-Green-Refactor**: Follow the TDD cycle strictly
   - **Red**: Write a failing test that defines desired behavior
   - **Green**: Write minimal code to make the test pass
   - **Refactor**: Improve code while keeping tests green
3. **Test Coverage**: Achieve minimum 90% code coverage for all Nix functions and shell scripts
4. **No Untested Code**: No implementation without corresponding tests

### Test Types & Requirements

#### Unit Tests (Build-Time Validation)

**Purpose**: Test individual Nix functions in isolation during build

**Requirements**:
- **TR-001**: MUST test `validateULID` function with valid and invalid ULID inputs
- **TR-002**: MUST test `generateManifest` function produces valid JSON conforming to Web App Manifest spec
- **TR-003**: MUST test `generateFirefoxPWAConfig` handles empty PWA lists, single PWA, multiple PWAs
- **TR-004**: MUST test ULID validation rejects ULIDs with forbidden characters (I, L, O, U)
- **TR-005**: MUST test ULID validation rejects ULIDs with incorrect length (<26 or >26 chars)
- **TR-006**: MUST test manifest generation includes all required fields (name, start_url, scope, icons, display)
- **TR-007**: MUST test manifest generation handles missing optional fields gracefully
- **TR-008**: MUST test config generation rejects duplicate ULIDs with clear error message

**Testing Framework**: Nix evaluation tests using `pkgs.runCommand` and assertion checks

**Location**: `/etc/nixos/tests/pwa-installation/unit/`

**Example Test Structure**:
```nix
# Test validateULID function
testValidULID = pkgs.runCommand "test-valid-ulid" {} ''
  result=$(${validateULID "01HQ1Z9J8G7X2K5MNBVWXYZ013"})
  if [ "$result" != "true" ]; then
    echo "FAIL: Valid ULID rejected"
    exit 1
  fi
  touch $out
'';

testInvalidULIDLength = pkgs.runCommand "test-invalid-ulid-length" {} ''
  result=$(${validateULID "01HQ1Z9J8G7X2K5MNBVWXYZ01"})  # 25 chars
  if [ "$result" != "false" ]; then
    echo "FAIL: Invalid ULID (length) accepted"
    exit 1
  fi
  touch $out
'';
```

#### Integration Tests (Runtime Validation)

**Purpose**: Test end-to-end PWA installation workflow in real NixOS environment

**Requirements**:
- **TR-009**: MUST test fresh system deployment → rebuild → PWAs installed automatically
- **TR-010**: MUST test idempotency - running installation twice produces identical results
- **TR-011**: MUST test cross-machine portability - same config on hetzner-sway, M1, WSL
- **TR-012**: MUST test PWA launches successfully via Walker after installation
- **TR-013**: MUST test desktop entry symlinks created in correct location
- **TR-014**: MUST test 1Password extension loads automatically in installed PWAs
- **TR-015**: MUST test helper commands (pwa-list, pwa-validate, pwa-install-all) function correctly
- **TR-016**: MUST test manifest URL accessibility during installation (file:// protocol)
- **TR-017**: MUST test installation failure handling - one PWA fails, others continue
- **TR-018**: MUST test metadata change propagation - update pwa-sites.nix → rebuild → changes reflected

**Testing Framework**: NixOS VM tests (`nixosTest`) with Selenium/Playwright for UI validation

**Location**: `/etc/nixos/tests/pwa-installation/integration/`

**Example Test Structure**:
```nix
# Integration test for User Story 1
testZeroTouchDeployment = makeTest {
  name = "pwa-zero-touch-deployment";
  nodes.machine = { ... }: {
    imports = [ ./configurations/test-config.nix ];
    # Enable firefox-pwas-declarative module
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # Verify PWAs installed without manual intervention
    output = machine.succeed("firefoxpwa profile list")
    assert "YouTube" in output, "YouTube PWA not installed"

    # Verify desktop entries exist
    machine.succeed("test -f ~/.local/share/applications/FFPWA-01HQ1Z9J8G7X2K5MNBVWXYZ013.desktop")

    # Test idempotency
    machine.succeed("pwa-install-all")
    output2 = machine.succeed("firefoxpwa profile list")
    assert output == output2, "Installation not idempotent"
  '';
};
```

#### Acceptance Tests (User Story Validation)

**Purpose**: Validate each user story meets acceptance criteria

**Requirements**:
- **TR-019**: MUST validate User Story 1 acceptance scenarios (all 3 scenarios)
- **TR-020**: MUST validate User Story 2 acceptance scenarios (all 3 scenarios)
- **TR-021**: MUST validate User Story 3 acceptance scenarios (all 3 scenarios)
- **TR-022**: MUST test all edge cases listed in spec (network failures, ULID collisions, manual uninstall, auth requirements)

**Testing Framework**: Bash scripts with BDD-style assertions

**Location**: `/etc/nixos/tests/pwa-installation/acceptance/`

**Example Test Structure**:
```bash
#!/usr/bin/env bash
# Test: User Story 1 - Scenario 1

# Given: NixOS configuration with PWA definitions
echo "Setting up test PWA in pwa-sites.nix..."
cat > /tmp/test-pwa-sites.nix << EOF
[{
  name = "TestPWA";
  url = "https://example.com";
  ulid = "01HQ1Z9J8G7X2K5MNBVWXYZ099";
  # ... other fields
}]
EOF

# When: System is rebuilt
nixos-rebuild switch --flake .#test-config

# Then: PWA appears in firefoxpwa profile list without manual installation
if firefoxpwa profile list | grep -q "TestPWA"; then
  echo "✓ PASS: TestPWA automatically installed"
else
  echo "✗ FAIL: TestPWA not found in profile list"
  exit 1
fi
```

### Test Coverage Requirements

- **Nix Functions**: 100% coverage (all functions must be tested)
- **Shell Scripts**: 90% coverage (critical paths fully tested)
- **User Stories**: 100% acceptance scenario coverage
- **Edge Cases**: 100% edge case coverage

### Testing Tools

- **Nix Tests**: `pkgs.runCommand`, `pkgs.writeShellScript` for assertions
- **NixOS VM Tests**: `nixosTest` for integration testing
- **Shell Testing**: `bats` (Bash Automated Testing System) for shell script tests
- **Coverage**: `nix-coverage` or manual coverage tracking via test logs
- **CI Integration**: Tests run automatically via NixOS `checks` output

### Test Data

**Test PWA Definitions** (in `/etc/nixos/tests/pwa-installation/fixtures/`):
- Minimal PWA: Only required fields
- Complete PWA: All optional fields populated
- Invalid PWA: Missing required fields (for error testing)
- Edge Case PWA: Localhost URL, special characters in name, remote icon

### Continuous Integration

**CI Pipeline**:
1. **Lint**: Check Nix syntax with `nixfmt`, `statix`
2. **Unit Tests**: Run all unit tests (`nix build .#checks.x86_64-linux.pwa-unit-tests`)
3. **Integration Tests**: Run NixOS VM tests (`nix build .#checks.x86_64-linux.pwa-integration-tests`)
4. **Acceptance Tests**: Run BDD acceptance tests
5. **Coverage Report**: Generate coverage report, fail if <90%
6. **Dry Build**: Test on all configurations (hetzner-sway, M1, WSL)

**CI Failure Policy**: Pipeline MUST fail if ANY test fails. No merging without green CI.

### Test Execution Order (TDD Cycle)

For each task in tasks.md:

1. **Write Test**: Create failing test that validates the requirement
2. **Verify Red**: Run test, confirm it fails
3. **Implement**: Write minimal code to pass the test
4. **Verify Green**: Run test, confirm it passes
5. **Refactor**: Improve code quality while keeping test green
6. **Commit**: Commit test + implementation together

**Example TDD Workflow for validateULID**:

```bash
# Step 1: Write failing test
cat > tests/pwa-installation/unit/test-validate-ulid.nix << EOF
testValidULID = assert (validateULID "01HQ1Z9J8G7X2K5MNBVWXYZ013") == true;
  pkgs.runCommand "test-valid-ulid" {} "touch $out";
EOF

# Step 2: Verify RED (test fails because validateULID doesn't exist yet)
nix build .#checks.x86_64-linux.test-valid-ulid
# Expected: ERROR - validateULID function not found

# Step 3: Implement minimal validateULID
cat > home-modules/tools/firefox-pwas-declarative.nix << EOF
validateULID = ulid:
  let
    validLength = builtins.stringLength ulid == 26;
    validChars = builtins.match "^[0-9A-HJKMNP-TV-Z]{26}$" ulid != null;
  in
    validLength && validChars;
EOF

# Step 4: Verify GREEN
nix build .#checks.x86_64-linux.test-valid-ulid
# Expected: Success

# Step 5: Refactor (improve error messages, add comments)

# Step 6: Commit
git add tests/pwa-installation/unit/test-validate-ulid.nix home-modules/tools/firefox-pwas-declarative.nix
git commit -m "Add validateULID with passing tests"
```

### Test-First Mandate

**CRITICAL**: All functional requirements (FR-001 to FR-014) MUST have corresponding tests written BEFORE implementation. Implementation without tests is BLOCKED.

**Test Review Checklist** (before implementation):
- [ ] Test written for requirement
- [ ] Test fails when run (RED phase verified)
- [ ] Test has clear assertion messages
- [ ] Test is independent (no dependencies on other tests)
- [ ] Test data is in fixtures, not hardcoded

---

## Non-Functional Requirements *(optional)*

### Performance

- PWA installation during system rebuild should complete within 2 minutes for 15 PWAs
- Manifest file generation should complete in under 5 seconds
- ULID generation and validation should be instantaneous (< 100ms total)
- **TR-023**: Unit tests MUST complete in under 30 seconds total
- **TR-024**: Integration tests MUST complete in under 5 minutes total

### Reliability

- PWA installation must be idempotent - same result regardless of how many times rebuild is run
- Configuration must gracefully handle network failures during manifest access
- System must preserve existing PWAs if declarative installation fails
- **TR-025**: Tests MUST be deterministic - same input produces same result every time
- **TR-026**: Tests MUST clean up after themselves (no side effects on test environment)

### Maintainability

- PWA metadata should be defined in one location (app-registry-data.nix)
- Generated files (manifests, ULIDs) should have clear source attribution
- Configuration should include inline documentation explaining ULID and manifest requirements
- **TR-027**: Test code MUST follow same quality standards as implementation code
- **TR-028**: Each test MUST have descriptive name explaining what it validates
