"""OpenTelemetry AI Assistant Monitor.

A service that receives OTLP telemetry from Claude Code and Codex CLI,
tracks session states, and outputs JSON streams for EWW consumption.

Feature: 123-otel-tracing
"""

__version__ = "0.5.0"  # Added process-based detection fallback for Codex
