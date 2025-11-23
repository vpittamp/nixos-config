"""
Window command models for Feature 091: Optimize i3pm Project Switching Performance.

This module provides Pydantic models for representing Sway IPC commands that can be
executed in parallel or batched for performance optimization.
"""

from __future__ import annotations

from enum import Enum
from typing import Any, Optional
from pydantic import BaseModel, Field


class CommandType(str, Enum):
    """Type of window command operation."""

    MOVE_WORKSPACE = "move_workspace"
    MOVE_SCRATCHPAD = "move_scratchpad"
    FLOATING_ENABLE = "floating_enable"
    FLOATING_DISABLE = "floating_disable"
    RESIZE = "resize"
    MOVE_POSITION = "move_position"
    FOCUS = "focus"


class WindowCommand(BaseModel):
    """Single Sway IPC command for a window.

    This model represents an atomic command that can be executed via Sway IPC.
    Commands are immutable to ensure thread safety when used with asyncio.gather().

    Attributes:
        window_id: Sway container/window ID (con_id)
        command_type: Type of command to execute
        params: Command-specific parameters (e.g., workspace_number, width, height)

    Example:
        >>> cmd = WindowCommand(
        ...     window_id=12345,
        ...     command_type=CommandType.MOVE_WORKSPACE,
        ...     params={"workspace_number": 3}
        ... )
        >>> print(cmd.to_sway_command())
        "[con_id=12345] move workspace number 3"
    """

    window_id: int = Field(..., description="Sway container/window ID", gt=0)
    command_type: CommandType = Field(..., description="Type of command")
    params: dict[str, Any] = Field(
        default_factory=dict, description="Command parameters"
    )

    def to_sway_command(self) -> str:
        """Generate Sway IPC command string.

        Returns:
            A Sway IPC command string that can be executed via i3ipc Connection.command()

        Raises:
            ValueError: If required parameters are missing for the command type
        """
        selector = f"[con_id={self.window_id}]"

        match self.command_type:
            case CommandType.MOVE_WORKSPACE:
                if "workspace_number" not in self.params:
                    raise ValueError(
                        "MOVE_WORKSPACE requires 'workspace_number' parameter"
                    )
                workspace_num = self.params["workspace_number"]
                return f"{selector} move workspace number {workspace_num}"

            case CommandType.MOVE_SCRATCHPAD:
                return f"{selector} move scratchpad"

            case CommandType.FLOATING_ENABLE:
                return f"{selector} floating enable"

            case CommandType.FLOATING_DISABLE:
                return f"{selector} floating disable"

            case CommandType.RESIZE:
                if "width" not in self.params or "height" not in self.params:
                    raise ValueError("RESIZE requires 'width' and 'height' parameters")
                width = self.params["width"]
                height = self.params["height"]
                return f"{selector} resize set {width} px {height} px"

            case CommandType.MOVE_POSITION:
                if "x" not in self.params or "y" not in self.params:
                    raise ValueError("MOVE_POSITION requires 'x' and 'y' parameters")
                x = self.params["x"]
                y = self.params["y"]
                return f"{selector} move position {x} px {y} px"

            case CommandType.FOCUS:
                return f"{selector} focus"

    class Config:
        """Pydantic model configuration."""

        frozen = True  # Immutable for thread safety


class CommandBatch(BaseModel):
    """Batch of commands that can be executed together.

    Represents a group of window commands that can either be executed in parallel
    (if targeting different windows) or batched into a single Sway IPC call
    (if targeting the same window with sequential dependencies).

    Attributes:
        window_id: Target window ID (all commands must target this window)
        commands: List of commands in execution order
        can_batch: Whether commands can be batched into single IPC call

    Example:
        >>> batch = CommandBatch.from_window_state(
        ...     window_id=12345,
        ...     workspace_num=3,
        ...     is_floating=True,
        ...     geometry={"x": 100, "y": 200, "width": 800, "height": 600}
        ... )
        >>> print(batch.to_batched_command())
        "[con_id=12345] move workspace number 3; floating enable; resize set 800 px 600 px; move position 100 px 200 px"
    """

    window_id: int = Field(..., description="Target window ID", gt=0)
    commands: list[WindowCommand] = Field(
        ..., description="Commands in execution order", min_length=1
    )
    can_batch: bool = Field(
        True, description="Whether commands can be batched into single IPC call"
    )

    def to_batched_command(self) -> str:
        """Generate single batched Sway command with semicolons.

        Combines multiple commands into a single Sway IPC call by chaining them
        with semicolons. This reduces round-trip latency for sequential operations.

        Returns:
            A batched Sway IPC command string

        Raises:
            ValueError: If commands cannot be batched or target different windows
        """
        if not self.can_batch or len(self.commands) == 0:
            raise ValueError("Cannot batch these commands")

        # All commands must target same window
        if not all(cmd.window_id == self.window_id for cmd in self.commands):
            raise ValueError("All commands in batch must target same window")

        # Generate commands without selector (we'll add it once)
        cmd_parts: list[str] = []
        selector = f"[con_id={self.window_id}]"

        for cmd in self.commands:
            sway_cmd = cmd.to_sway_command()
            # Remove selector prefix if present
            cmd_text = sway_cmd.replace(selector, "").strip()
            cmd_parts.append(cmd_text)

        # Join with semicolons and add selector once
        return f"{selector} {'; '.join(cmd_parts)}"

    @classmethod
    def from_window_state(
        cls,
        window_id: int,
        workspace_num: int,
        is_floating: bool,
        geometry: Optional[dict[str, int]] = None,
    ) -> CommandBatch:
        """Create command batch for restoring a window.

        This factory method creates a batch of commands to restore a window to its
        original state after being hidden to scratchpad. Commands are ordered to
        ensure proper restoration sequence.

        Args:
            window_id: Sway container ID
            workspace_num: Target workspace number
            is_floating: Whether window should be floating
            geometry: Optional geometry dict with x, y, width, height

        Returns:
            A CommandBatch configured for window restoration
        """
        commands: list[WindowCommand] = [
            WindowCommand(
                window_id=window_id,
                command_type=CommandType.MOVE_WORKSPACE,
                params={"workspace_number": workspace_num},
            )
        ]

        if is_floating:
            commands.append(
                WindowCommand(
                    window_id=window_id,
                    command_type=CommandType.FLOATING_ENABLE,
                    params={},
                )
            )

            if geometry:
                commands.append(
                    WindowCommand(
                        window_id=window_id,
                        command_type=CommandType.RESIZE,
                        params={
                            "width": geometry["width"],
                            "height": geometry["height"],
                        },
                    )
                )
                commands.append(
                    WindowCommand(
                        window_id=window_id,
                        command_type=CommandType.MOVE_POSITION,
                        params={"x": geometry["x"], "y": geometry["y"]},
                    )
                )
        else:
            commands.append(
                WindowCommand(
                    window_id=window_id,
                    command_type=CommandType.FLOATING_DISABLE,
                    params={},
                )
            )

        return cls(window_id=window_id, commands=commands, can_batch=True)
