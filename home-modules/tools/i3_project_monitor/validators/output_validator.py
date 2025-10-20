"""Output/monitor configuration validator.

Validates monitor configuration using i3's GET_OUTPUTS data.
Ensures at least one active output exists and validates output properties.
"""

from dataclasses import dataclass, field
from typing import List, Optional

from ..models import OutputState


@dataclass
class OutputValidationResult:
    """Result of output validation."""

    valid: bool
    errors: List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    active_outputs: List[OutputState] = field(default_factory=list)
    inactive_outputs: List[OutputState] = field(default_factory=list)
    primary_output: Optional[OutputState] = None

    def __bool__(self) -> bool:
        """Allow using result in boolean context."""
        return self.valid


def validate_output_configuration(
    outputs: List[OutputState]
) -> OutputValidationResult:
    """Validate monitor/output configuration.

    Checks:
    1. At least one output exists
    2. At least one output is active
    3. At most one output is marked as primary
    4. All active outputs have valid dimensions
    5. Output names are unique

    Args:
        outputs: List of output states from GET_OUTPUTS

    Returns:
        OutputValidationResult with validation status and issues
    """
    result = OutputValidationResult(valid=True)

    # Check 1: At least one output exists
    if not outputs:
        result.valid = False
        result.errors.append("No outputs found")
        return result

    # Categorize outputs
    active_outputs = []
    inactive_outputs = []
    primary_outputs = []
    output_names = set()

    for output in outputs:
        # Check for duplicate names
        if output.name in output_names:
            result.valid = False
            result.errors.append(f"Duplicate output name: '{output.name}'")
        output_names.add(output.name)

        # Categorize
        if output.active:
            active_outputs.append(output)
        else:
            inactive_outputs.append(output)

        if output.primary:
            primary_outputs.append(output)

    result.active_outputs = active_outputs
    result.inactive_outputs = inactive_outputs

    # Check 2: At least one active output
    if not active_outputs:
        result.valid = False
        result.errors.append("No active outputs found")
        return result

    # Check 3: At most one primary output
    if len(primary_outputs) > 1:
        result.valid = False
        primary_names = [f"'{o.name}'" for o in primary_outputs]
        result.errors.append(
            f"Multiple outputs marked as primary: {', '.join(primary_names)}"
        )
    elif len(primary_outputs) == 1:
        result.primary_output = primary_outputs[0]
    else:
        result.warnings.append("No primary output configured")

    # Check 4: Active outputs have valid dimensions
    for output in active_outputs:
        if output.width <= 0 or output.height <= 0:
            result.valid = False
            result.errors.append(
                f"Active output '{output.name}' has invalid dimensions: "
                f"{output.width}x{output.height}"
            )

    # Additional checks
    if inactive_outputs:
        inactive_names = [o.name for o in inactive_outputs]
        result.warnings.append(
            f"Inactive outputs detected: {', '.join(inactive_names)}"
        )

    return result


def check_primary_output_exists(outputs: List[OutputState]) -> bool:
    """Quick check: at least one primary output exists.

    Args:
        outputs: List of output states

    Returns:
        True if at least one output is marked as primary
    """
    return any(o.primary for o in outputs)


def check_active_outputs(outputs: List[OutputState]) -> List[OutputState]:
    """Get all active outputs.

    Args:
        outputs: List of output states

    Returns:
        List of active outputs
    """
    return [o for o in outputs if o.active]


def get_primary_output(outputs: List[OutputState]) -> Optional[OutputState]:
    """Get the primary output.

    Args:
        outputs: List of output states

    Returns:
        The primary output, or None if no primary output is configured
    """
    primary = [o for o in outputs if o.primary]
    return primary[0] if primary else None


def get_output_by_name(
    outputs: List[OutputState],
    name: str
) -> Optional[OutputState]:
    """Get output by name.

    Args:
        outputs: List of output states
        name: Output name to search for

    Returns:
        The output with the given name, or None if not found
    """
    for output in outputs:
        if output.name == name:
            return output
    return None


def check_output_geometry_valid(output: OutputState) -> bool:
    """Check if output has valid geometry.

    Args:
        output: Output state to check

    Returns:
        True if output has valid dimensions (width > 0 and height > 0)
    """
    return output.width > 0 and output.height > 0


def get_total_display_area(outputs: List[OutputState]) -> tuple[int, int]:
    """Calculate total display area from active outputs.

    Computes the bounding box that contains all active outputs.

    Args:
        outputs: List of output states

    Returns:
        Tuple of (total_width, total_height) of bounding box
    """
    active = [o for o in outputs if o.active]

    if not active:
        return (0, 0)

    # Find bounding box
    min_x = min(o.x for o in active)
    min_y = min(o.y for o in active)
    max_x = max(o.x + o.width for o in active)
    max_y = max(o.y + o.height for o in active)

    return (max_x - min_x, max_y - min_y)
