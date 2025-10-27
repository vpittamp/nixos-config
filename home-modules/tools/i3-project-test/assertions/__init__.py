"""Assertion modules for i3 project test framework.

This package provides assertion functions for validating daemon state,
i3 IPC state, and cross-validation between them.
"""

from .i3_assertions import I3Assertions
from .output_assertions import OutputAssertions
from .state_assertions import StateAssertions
from .launch_assertions import LaunchAssertions  # Feature 041: IPC Launch Context - T015


__all__ = [
    "StateAssertions",
    "I3Assertions",
    "OutputAssertions",
    "LaunchAssertions",
]
