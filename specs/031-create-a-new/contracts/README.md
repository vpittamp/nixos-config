# API Contracts: i3 Window Rules Discovery

This directory contains JSON Schema definitions for the i3 window rules discovery and validation system.

## Schemas

### window-rules.schema.json

Defines the structure for `window-rules.json` which stores window matching patterns and workspace assignments.

**Location**: `~/.config/i3/window-rules.json`

**Purpose**: Maps window patterns (WM_CLASS or title) to workspace assignments with scope classification.

**Key Fields**:
- `rules[]`: Array of window rules
- `rules[].pattern`: Pattern definition (type, value, priority)
- `rules[].workspace`: Target workspace number (1-9)
- `rules[].scope`: "scoped" or "global"
- `rules[].application_name`: Friendly name for the application

**Usage**: Read by i3-project-event-listener daemon during window::new events.

### app-classes.schema.json

Defines the structure for `app-classes.json` which classifies window classes as scoped or global.

**Location**: `~/.config/i3/app-classes.json`

**Purpose**: Determines which applications are project-specific (hidden when project inactive) vs always visible.

**Key Fields**:
- `scoped_classes[]`: Window classes for project-scoped applications
- `global_classes[]`: Window classes for globally visible applications

**Usage**: Read by daemon to determine window visibility during project switches.

### application-registry.schema.json

Defines the structure for `application-registry.json` which catalogs applications with launch commands and pattern expectations.

**Location**: `~/.config/i3/application-registry.json` (new file created by this feature)

**Purpose**: Provides discovery tool with application launch commands, parameter substitution, and expected patterns.

**Key Fields**:
- `applications[]`: Array of application definitions
- `applications[].name`: Application identifier
- `applications[].command`: Base launch command
- `applications[].parameters`: Command parameters with variable substitution ($PROJECT_DIR)
- `applications[].expected_pattern_type`: Expected pattern type (class/title/pwa)
- `applications[].scope`: "scoped" or "global"
- `applications[].preferred_workspace`: Target workspace number

**Usage**: Read by discovery tool to launch applications and generate patterns.

## Validation

Use `jsonschema` library to validate configuration files:

```python
import json
import jsonschema

# Load schema
with open('contracts/window-rules.schema.json') as f:
    schema = json.load(f)

# Load configuration
with open('~/.config/i3/window-rules.json') as f:
    config = json.load(f)

# Validate
jsonschema.validate(instance=config, schema=schema)
```

## Version History

- **1.0.0** (2025-10-23): Initial schemas for Feature 031
