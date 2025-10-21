# Docstring Style Guide

**T096: Comprehensive docstrings for all public APIs**

This project uses **Google-style docstrings** for all Python code.

## Format

```python
def function_name(param1: type1, param2: type2) -> return_type:
    """One-line summary ending with a period.

    Multi-line description if needed. Explain what the function does,
    not how it does it. Include usage context and important notes.

    Args:
        param1: Description of param1. Type hints already in signature.
        param2: Description of param2.

    Returns:
        Description of return value. Type hint already in signature.

    Raises:
        ExceptionType: When this exception is raised.

    Examples:
        >>> function_name(arg1, arg2)
        expected_result

    Notes:
        Additional information, caveats, or warnings.

    References:
        Task IDs (T001), Feature Requirements (FR-001), Success Criteria (SC-001)
    """
```

## Module Docstrings

Every module should have a docstring at the top:

```python
"""Brief module description.

Detailed description of what this module provides.
List main classes/functions exported.

T096: Task reference
FR-XXX: Feature requirement
"""
```

## Class Docstrings

```python
class ClassName:
    """Brief class description.

    Detailed description of the class purpose and usage.

    Attributes:
        attr1: Description of attribute1.
        attr2: Description of attribute2.

    Examples:
        >>> obj = ClassName(param1, param2)
        >>> obj.method()
        result

    T096: Task reference
    """
```

## Best Practices

1. **Be Concise**: First line should be a complete sentence < 80 chars
2. **Be Complete**: Include all args, returns, raises, examples
3. **Be Accurate**: Keep docstrings in sync with code
4. **Be Helpful**: Include examples for complex functions
5. **Reference Tasks**: Include T-numbers and FR-numbers where relevant

## What to Document

### Must Document:
- ✅ All public modules (files)
- ✅ All public classes
- ✅ All public functions/methods
- ✅ All public constants

### Optional:
- Private methods (leading `_`) if complex
- Internal helper functions if non-obvious

### Don't Document:
- Trivial getters/setters
- `__init__` if just stores parameters
- Obvious property accessors

## Examples from Project

### Good Example (models/project.py):
```python
class Project:
    """Represents an i3 project with configuration and state.

    A project groups windows by context (e.g., NixOS, Stacks, Personal).
    Windows are shown/hidden based on active project.

    Attributes:
        name: Unique project identifier (alphanumeric, dashes, underscores).
        display_name: Human-readable name for UI display.
        directory: Project directory path.
        icon: Unicode emoji icon for visual identification.
        scoped_classes: Window classes that belong to this project.

    Examples:
        >>> project = Project(
        ...     name="nixos",
        ...     directory=Path("/etc/nixos"),
        ...     display_name="NixOS Config",
        ...     icon="❄️"
        ... )
        >>> project.scoped_classes.add("Code")
        >>> project.save()

    T021: Project model implementation
    FR-010: Project CRUD operations
    """
```

### Good Example (cli/commands.py):
```python
async def cmd_switch(args: argparse.Namespace) -> int:
    """Switch to a project and show its windows.

    Hides windows from other projects and shows windows that belong to
    the target project. Optionally auto-launches configured applications.

    Args:
        args: Parsed command-line arguments containing:
            - project: Project name to switch to
            - no_launch: Skip auto-launching apps if True
            - json: Output in JSON format if True

    Returns:
        Exit code: 0 on success, 1 on error.

    Examples:
        >>> await cmd_switch(Namespace(project="nixos", no_launch=False))
        0

    T012: Switch command implementation
    FR-020: Project switching with <100ms latency
    SC-015: Auto-launch applications on switch
    """
```

### Good Example (tui/inspector.py):
```python
async def inspect_window_focused() -> WindowProperties:
    """Inspect currently focused window using i3 IPC.

    Queries i3 for the focused window and extracts all properties including
    WM_CLASS, title, marks, classification, and pattern matches.

    Returns:
        WindowProperties object with all extracted data.

    Raises:
        ValueError: If no window is currently focused.
        ConnectionError: If i3 IPC connection fails.

    Examples:
        >>> props = await inspect_window_focused()
        >>> print(f"Focused window: {props.window_class}")
        Focused window: Code

    T076: Focused window inspection
    FR-111: Inspector window selection modes
    """
```

## Verification

Check docstring coverage with:

```bash
# Check for missing docstrings
ruff check --select D

# Generate documentation
pydoc-markdown

# Validate style
pydocstyle i3_project_manager/
```

## References

- [Google Python Style Guide](https://google.github.io/styleguide/pyguide.html#38-comments-and-docstrings)
- [PEP 257 – Docstring Conventions](https://peps.python.org/pep-0257/)
- [Napoleon - Sphinx extension for Google style](https://www.sphinx-doc.org/en/master/usage/extensions/napoleon.html)

---

**Last updated**: 2025-10-21 (T096 implementation)
