# Mark Serialization Format Contract

**Feature**: 051-i3run-scratchpad-enhancement
**Contract Type**: Data Serialization Format
**Version**: 1.0
**Date**: 2025-11-06

## Format Specification

### Scratchpad Combined Identity+State Mark

**Purpose**: Store both terminal identity AND state in single mark (Sway allows ONE mark per window).

**Format**:
```
scratchpad:{project_name}|floating:{bool},x:{int},y:{int},w:{int},h:{int},ts:{int},ws:{int},mon:{str}
```

**Example**:
```
scratchpad:nixos|floating:true,x:100,y:200,w:1000,h:600,ts:1730934000,ws:1,mon:HEADLESS-1
```

**Components**:
- **Prefix**: `scratchpad:` (identity namespace)
- **Project**: `{project_name}` (e.g., `nixos`, `dotfiles`)
- **Separator**: `|` (divides identity from state)
- **State Fields**: Comma-delimited key:value pairs

### Field Definitions

| Key | Type | Required | Description | Example |
|-----|------|----------|-------------|---------|
| `floating` | bool | Yes | Floating vs tiling | `true` or `false` |
| `x` | int | Yes | X position (pixels) | `100` |
| `y` | int | Yes | Y position (pixels) | `200` |
| `w` | int | Yes | Width (pixels) | `1000` |
| `h` | int | Yes | Height (pixels) | `600` |
| `ts` | int | Yes | Unix timestamp | `1730934000` |
| `ws` | int | Yes | Workspace number | `1` |
| `mon` | str | Yes | Monitor name | `HEADLESS-1` |

### Parsing Algorithm

```python
def from_mark_string(mark: str) -> Optional[ScratchpadState]:
    """Parse mark string into ScratchpadState."""
    try:
        # Step 1: Validate prefix
        if not mark.startswith("scratchpad:"):
            return None

        # Step 2: Split identity and state
        mark_body = mark.replace("scratchpad:", "")
        if "|" not in mark_body:
            # Legacy format without state (identity only)
            return None

        project_name, state_str = mark_body.split("|", 1)

        # Step 3: Parse key-value pairs
        state_dict = {}
        for pair in state_str.split(","):
            key, value = pair.split(":", 1)
            state_dict[key] = value

        # Step 4: Construct model with type conversion
        return ScratchpadState(
            project_name=project_name,
            floating=state_dict["floating"] == "true",
            x=int(state_dict["x"]),
            y=int(state_dict["y"]),
            width=int(state_dict["w"]),
            height=int(state_dict["h"]),
            workspace_num=int(state_dict["ws"]),
            monitor_name=state_dict["mon"],
            timestamp=int(state_dict["ts"])
        )
    except (ValueError, KeyError, IndexError):
        return None  # Graceful degradation on invalid format
```

### Serialization Algorithm

```python
def to_mark_string(state: ScratchpadState) -> str:
    """Serialize state to mark string with combined identity+state."""
    return (
        f"scratchpad:{state.project_name}|"
        f"floating:{'true' if state.floating else 'false'},"
        f"x:{state.x},y:{state.y},"
        f"w:{state.width},h:{state.height},"
        f"ts:{state.timestamp},"
        f"ws:{state.workspace_num},"
        f"mon:{state.monitor_name}"
    )
```

### Constraints

1. **One mark per window**: Sway allows only ONE mark per window. New marks replace previous.
2. **Character support**: All characters supported (`:`, `=`, `,`tested and validated)
3. **Max length**: No hard limit (tested 2000+ chars), recommend <500 chars
4. **Delimiter conflict**: No conflict with values (monitor names don't contain `:` or `=`)

### Error Handling

**Invalid Format**: Return `None` from parser (graceful degradation)

**Missing Fields**: Use defaults or fail to parse
```python
width=int(state_dict.get("w", "1000"))  # Default to 1000 if missing
```

**Type Conversion Failure**: Catch ValueError and return None

### Validation Tests

```python
def test_mark_serialization():
    state = ScratchpadState(
        project_name="test",
        floating=True,
        x=100, y=200,
        width=1000, height=600,
        workspace_num=1,
        monitor_name="HEADLESS-1",
        timestamp=1730934000
    )

    # Serialize
    mark = state.to_mark_string()
    assert mark == "scratchpad:test|floating:true,x:100,y:200,w:1000,h:600,ts:1730934000,ws:1,mon:HEADLESS-1"

    # Deserialize
    restored = ScratchpadState.from_mark_string(mark)
    assert restored.project_name == "test"
    assert restored.x == 100
    assert restored.floating is True

    # Round-trip
    assert restored.to_mark_string() == mark
```

## Version Compatibility

**Current Version**: 1.0

**Future Extensions**: Add new fields to end, maintain backward compatibility:
```
# v1.1 might add opacity field:
scratchpad:nixos|floating:true,x:100,y:200,w:1000,h:600,ts:1730934000,ws:1,mon:HEADLESS-1,opacity:0.9
```

Parser must handle missing fields with defaults for backward compatibility.

**Migration from Feature 062**:
- Feature 062 uses: `scratchpad:{project}` (identity only)
- Feature 051 uses: `scratchpad:{project}|{state}` (identity + state)
- Parser checks for `|` separator to detect new format
- Legacy marks without `|` are treated as identity-only (no state to restore)
