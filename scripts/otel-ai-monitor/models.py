"""Pydantic models for OpenTelemetry AI Assistant Monitor.

This module defines the data models for session tracking and JSON output.
Based on the data model specification in specs/123-otel-tracing/data-model.md
and specs/125-tracing-parity-codex/data-model.md.
"""

from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


class SessionState(str, Enum):
    """Session state machine states."""

    IDLE = "idle"
    WORKING = "working"
    COMPLETED = "completed"
    EXPIRED = "expired"


class AITool(str, Enum):
    """Supported AI assistant tools."""

    CLAUDE_CODE = "claude-code"
    CODEX_CLI = "codex"
    GEMINI_CLI = "gemini"


class Provider(str, Enum):
    """AI service providers for cost calculation and attribute mapping."""

    ANTHROPIC = "anthropic"
    OPENAI = "openai"
    GOOGLE = "google"


# Provider pricing tables (USD per 1M tokens)
# Source: research.md from feature 125-tracing-parity-codex
PROVIDER_PRICING: dict[str, dict[str, tuple[float, float]]] = {
    # Anthropic models (input, output)
    Provider.ANTHROPIC: {
        "claude-opus-4-5": (15.00, 75.00),
        "claude-opus-4-5-20251101": (15.00, 75.00),
        "claude-sonnet-4": (3.00, 15.00),
        "claude-sonnet-4-20250514": (3.00, 15.00),
        "claude-3-5-haiku": (0.80, 4.00),
        "claude-3-5-haiku-20241022": (0.80, 4.00),
        "claude-3-5-sonnet": (3.00, 15.00),
        "claude-3-5-sonnet-20241022": (3.00, 15.00),
        # Older models
        "claude-3-opus": (15.00, 75.00),
        "claude-3-sonnet": (3.00, 15.00),
        "claude-3-haiku": (0.25, 1.25),
    },
    # OpenAI models (input, output)
    Provider.OPENAI: {
        "gpt-4o": (2.50, 10.00),
        "gpt-4o-2024-11-20": (2.50, 10.00),
        "gpt-4o-mini": (0.15, 0.60),
        "gpt-4o-mini-2024-07-18": (0.15, 0.60),
        "gpt-5-codex": (2.50, 10.00),  # Assume same as gpt-4o for now
        "o1": (15.00, 60.00),
        "o1-preview": (15.00, 60.00),
        "o1-mini": (3.00, 12.00),
        "o3-mini": (1.10, 4.40),
    },
    # Google models (input, output)
    Provider.GOOGLE: {
        "gemini-2.0-flash": (0.075, 0.30),
        "gemini-2.0-flash-exp": (0.075, 0.30),
        "gemini-2.5-flash": (0.075, 0.30),
        "gemini-2.5-flash-lite": (0.05, 0.20),
        "gemini-2.5-pro": (1.25, 5.00),
        "gemini-1.5-pro": (1.25, 5.00),
        "gemini-1.5-flash": (0.075, 0.30),
        "gemini-3-flash-preview": (0.10, 0.40),  # Estimated
        "gemini-3-pro-preview": (2.50, 10.00),  # Estimated
        "gemini-3-pro-preview-11-2025": (2.50, 10.00),  # Estimated
    },
}

# Default rate for unrecognized models (USD per 1M tokens)
DEFAULT_PRICING = (5.00, 15.00)  # Conservative estimate

# Provider detection mappings from service.name or gen_ai.system
PROVIDER_DETECTION: dict[str, Provider] = {
    "anthropic": Provider.ANTHROPIC,
    "claude-code": Provider.ANTHROPIC,
    "claude": Provider.ANTHROPIC,
    "openai": Provider.OPENAI,
    "codex": Provider.OPENAI,
    "google": Provider.GOOGLE,
    "gemini": Provider.GOOGLE,
    "gemini-cli": Provider.GOOGLE,
}

# Session ID attribute priority per provider
SESSION_ID_ATTRIBUTES: dict[Provider, list[str]] = {
    Provider.ANTHROPIC: ["session.id", "thread_id", "conversation_id"],
    Provider.OPENAI: ["conversation_id", "session.id"],
    Provider.GOOGLE: ["session.id", "conversation.id"],
}

# Tool to Provider mapping
TOOL_PROVIDER: dict[AITool, Provider] = {
    AITool.CLAUDE_CODE: Provider.ANTHROPIC,
    AITool.CODEX_CLI: Provider.OPENAI,
    AITool.GEMINI_CLI: Provider.GOOGLE,
}


class Session(BaseModel):
    """An active AI assistant session.

    Represents a tracked conversation identified by thread/conversation ID.
    Tracks state transitions and optional token metrics.
    """

    session_id: str = Field(
        description="Unique identifier from telemetry (thread_id or conversation.id)"
    )
    tool: AITool = Field(description="Which AI tool this session belongs to")
    provider: Provider = Field(
        default=Provider.ANTHROPIC,
        description="AI service provider for cost calculation"
    )
    state: SessionState = Field(
        default=SessionState.IDLE, description="Current session state"
    )
    project: Optional[str] = Field(
        default=None, description="Project context if available from telemetry"
    )
    window_id: Optional[int] = Field(
        default=None, description="Sway container ID of originating terminal window"
    )
    model: Optional[str] = Field(
        default=None, description="LLM model name for cost calculation"
    )
    cost_estimated: bool = Field(
        default=False, description="True if cost uses default rate (model not in pricing table)"
    )

    # Timestamps
    created_at: datetime = Field(description="When session was first detected")
    last_event_at: datetime = Field(description="When last telemetry event was received")
    state_changed_at: datetime = Field(description="When state last transitioned")

    # Metrics (optional, for P3 user story)
    input_tokens: int = Field(default=0, description="Cumulative input tokens")
    output_tokens: int = Field(default=0, description="Cumulative output tokens")
    cache_tokens: int = Field(default=0, description="Cumulative cache tokens")
    cost_usd: float = Field(default=0.0, description="Cumulative cost in USD")
    error_count: int = Field(default=0, description="Cumulative error count")
    last_error_type: Optional[str] = Field(default=None, description="Last error type if any")

    class Config:
        """Pydantic configuration."""

        use_enum_values = True


class TelemetryEvent(BaseModel):
    """Parsed telemetry event from OTLP log record.

    Represents a single event extracted from an OTLP ExportLogsServiceRequest.
    Used internally for session state updates.
    """

    event_name: str = Field(
        description="Event type (e.g., claude_code.user_prompt, codex.api_request)"
    )
    timestamp: datetime = Field(description="Event timestamp from telemetry")

    # Session identification
    session_id: Optional[str] = Field(
        default=None, description="thread_id, conversation_id, or conversation.id"
    )
    tool: Optional[AITool] = Field(
        default=None, description="Inferred from service.name or event prefix"
    )

    # Event-specific attributes
    attributes: dict = Field(
        default_factory=dict, description="All attributes from the log record"
    )

    # Trace context (for correlation)
    trace_id: Optional[str] = Field(default=None, description="OTLP trace ID")
    span_id: Optional[str] = Field(default=None, description="OTLP span ID")

    class Config:
        """Pydantic configuration."""

        use_enum_values = True


class SessionUpdate(BaseModel):
    """Output event for EWW deflisten consumption.

    Emitted immediately on session state changes for real-time UI updates.
    """

    type: str = Field(default="session_update", description="Event type for consumer routing")
    session_id: str = Field(description="Session identifier")
    tool: str = Field(description="AI tool type (claude-code or codex)")
    state: str = Field(description="Current session state")
    project: Optional[str] = Field(default=None, description="Project context if available")
    timestamp: int = Field(description="Unix timestamp in seconds")
    metrics: Optional[dict] = Field(
        default=None, description="Token counts if available"
    )


class SessionListItem(BaseModel):
    """Session summary for list output."""

    session_id: str = Field(description="Session identifier")
    tool: str = Field(description="AI tool type")
    state: str = Field(description="Current session state")
    project: Optional[str] = Field(default=None, description="Project context")
    window_id: Optional[int] = Field(default=None, description="Sway container ID for focus")


class SessionList(BaseModel):
    """Full session list output.

    Broadcast periodically for EWW initialization and recovery.
    Allows widgets to get full state on startup or after reconnection.
    """

    type: str = Field(default="session_list", description="Event type for consumer routing")
    sessions: list[SessionListItem] = Field(
        default_factory=list, description="All active sessions"
    )
    timestamp: int = Field(description="Unix timestamp in seconds")
    has_working: bool = Field(
        default=False, description="True if any session is in working state"
    )


# Event name constants for state machine triggers
class EventNames:
    """Known event names from Claude Code, Codex CLI, and Gemini CLI telemetry."""

    # Claude Code events
    CLAUDE_USER_PROMPT = "claude_code.user_prompt"
    CLAUDE_TOOL_RESULT = "claude_code.tool_result"
    CLAUDE_API_REQUEST = "claude_code.api_request"
    CLAUDE_API_ERROR = "claude_code.api_error"
    # Interceptor / derived spans (kept distinct from native log events)
    CLAUDE_LLM_CALL = "claude_code.llm_call"

    # Codex CLI events
    CODEX_CONVERSATION_STARTS = "codex.conversation_starts"
    CODEX_USER_PROMPT = "codex.user_prompt"
    CODEX_API_REQUEST = "codex.api_request"
    CODEX_SSE_EVENT = "codex.sse_event"
    CODEX_TOOL_DECISION = "codex.tool_decision"
    CODEX_TOOL_RESULT = "codex.tool_result"

    # Gemini CLI events
    # NOTE: Gemini CLI uses underscore-style event names (gemini_cli.api_request, ...)
    # Some docs/tools also refer to dot-style variants; keep both for compatibility.
    GEMINI_CONFIG = "gemini_cli.config"
    GEMINI_USER_PROMPT = "gemini_cli.user_prompt"
    GEMINI_API_REQUEST = "gemini_cli.api_request"
    GEMINI_API_RESPONSE = "gemini_cli.api_response"
    GEMINI_API_ERROR = "gemini_cli.api_error"
    GEMINI_TOOL_CALL = "gemini_cli.tool_call"
    GEMINI_API_REQUEST_DOT = "gemini_cli.api.request"
    GEMINI_API_RESPONSE_DOT = "gemini_cli.api.response"
    GEMINI_API_ERROR_DOT = "gemini_cli.api.error"
    GEMINI_TOKEN_USAGE = "gemini_cli.token.usage"
    # GenAI semantic convention events (used by Gemini CLI)
    GENAI_TOKEN_USAGE = "gen_ai.client.token.usage"
    GENAI_OPERATION = "gen_ai.client.operation"

    # Events that trigger WORKING state
    # Note: claude_code.api_request is included because Claude Code doesn't emit
    # explicit user_prompt events - API requests indicate user activity
    WORKING_TRIGGERS = {
        CLAUDE_USER_PROMPT,
        CLAUDE_API_REQUEST,  # Claude Code uses this to indicate activity
        CLAUDE_LLM_CALL,
        CODEX_USER_PROMPT,
        CODEX_CONVERSATION_STARTS,
        GEMINI_USER_PROMPT,
        GEMINI_API_REQUEST,
        GEMINI_API_REQUEST_DOT,
    }

    # Claude Code additional events
    CLAUDE_TOOL_DECISION = "claude_code.tool_decision"
    CLAUDE_AGENT_RUN = "claude_code.agent_run"  # From trace spans

    # Events that reset the quiet timer (keep WORKING)
    ACTIVITY_EVENTS = {
        CLAUDE_TOOL_RESULT,
        CLAUDE_API_REQUEST,
        CLAUDE_LLM_CALL,
        CLAUDE_TOOL_DECISION,  # Claude Code emits this for tool calls
        CLAUDE_AGENT_RUN,  # From trace spans
        CODEX_API_REQUEST,
        CODEX_SSE_EVENT,
        CODEX_TOOL_DECISION,
        CODEX_TOOL_RESULT,
        GEMINI_API_REQUEST,
        GEMINI_API_REQUEST_DOT,
        GEMINI_API_RESPONSE,
        GEMINI_API_RESPONSE_DOT,
        GEMINI_API_ERROR,
        GEMINI_API_ERROR_DOT,
        GEMINI_TOKEN_USAGE,
        GEMINI_TOOL_CALL,
        GENAI_TOKEN_USAGE,
        GENAI_OPERATION,
    }

    @staticmethod
    def get_tool_from_event(event_name: str) -> Optional[AITool]:
        """Infer AI tool from event name prefix."""
        if event_name.startswith("claude_code."):
            return AITool.CLAUDE_CODE
        elif event_name.startswith("codex."):
            return AITool.CODEX_CLI
        elif event_name.startswith("gemini_cli.") or event_name.startswith("gen_ai."):
            return AITool.GEMINI_CLI
        return None


# =============================================================================
# Feature 132: Langfuse OTEL Attribute Constants
# =============================================================================
# Langfuse uses OpenInference semantic conventions for trace type detection.
# These constants define the attribute names and valid values for Langfuse
# to properly categorize and display AI CLI traces.
#
# Reference: https://langfuse.com/docs/open-source/observability/opentelemetry

class LangfuseAttributes:
    """Langfuse-specific OTEL span attribute names and values.

    Langfuse's OTLP receiver maps OpenTelemetry spans to Langfuse observations
    using these attribute names. Proper attribute tagging ensures traces appear
    correctly in the Langfuse UI with proper hierarchy and metadata.
    """

    # --- Observation Type Attributes ---
    # Langfuse determines observation type from openinference.span.kind
    SPAN_KIND = "openinference.span.kind"

    # --- Span Kind Values (maps to Langfuse observation types) ---
    # CHAIN -> "span" in Langfuse (parent trace or workflow)
    # LLM -> "generation" in Langfuse (LLM API calls)
    # TOOL -> "span" with tool metadata in Langfuse
    # AGENT -> "span" in Langfuse (agent turns/steps)
    KIND_CHAIN = "CHAIN"
    KIND_LLM = "LLM"
    KIND_TOOL = "TOOL"
    KIND_AGENT = "AGENT"
    KIND_RETRIEVER = "RETRIEVER"
    KIND_EMBEDDING = "EMBEDDING"
    KIND_RERANKER = "RERANKER"

    # --- GenAI Semantic Convention Attributes ---
    # These are standard OpenTelemetry GenAI attributes that Langfuse recognizes
    GEN_AI_SYSTEM = "gen_ai.system"
    GEN_AI_REQUEST_MODEL = "gen_ai.request.model"
    GEN_AI_RESPONSE_MODEL = "gen_ai.response.model"
    GEN_AI_USAGE_INPUT_TOKENS = "gen_ai.usage.input_tokens"
    GEN_AI_USAGE_OUTPUT_TOKENS = "gen_ai.usage.output_tokens"
    GEN_AI_USAGE_TOTAL_TOKENS = "gen_ai.usage.total_tokens"
    GEN_AI_USAGE_COST = "gen_ai.usage.cost"

    # --- Langfuse-Specific Attributes ---
    # These attributes are specific to Langfuse and used for enhanced features
    LANGFUSE_SESSION_ID = "langfuse.session.id"
    LANGFUSE_USER_ID = "langfuse.user.id"
    LANGFUSE_TRACE_NAME = "langfuse.trace.name"
    LANGFUSE_OBSERVATION_NAME = "langfuse.observation.name"
    LANGFUSE_TAGS = "langfuse.tags"
    LANGFUSE_METADATA = "langfuse.metadata"
    LANGFUSE_VERSION = "langfuse.version"
    LANGFUSE_RELEASE = "langfuse.release"

    # --- Usage Details (JSON object) ---
    # Langfuse supports detailed token breakdown in usage_details
    LANGFUSE_USAGE_DETAILS = "langfuse.observation.usage_details"
    LANGFUSE_COST_DETAILS = "langfuse.observation.cost_details"

    # --- Tool Call Attributes ---
    TOOL_NAME = "tool.name"
    TOOL_DESCRIPTION = "tool.description"
    TOOL_INPUT = "input.value"
    TOOL_OUTPUT = "output.value"

    # --- Input/Output for Generations ---
    INPUT_VALUE = "input.value"
    INPUT_MIME_TYPE = "input.mime_type"
    OUTPUT_VALUE = "output.value"
    OUTPUT_MIME_TYPE = "output.mime_type"

    # --- OpenInference Message Attributes ---
    # For structured prompt/response content
    LLM_INPUT_MESSAGES = "llm.input_messages"
    LLM_OUTPUT_MESSAGES = "llm.output_messages"
    LLM_PROMPTS = "llm.prompts"
    LLM_PROMPT_TEMPLATE = "llm.prompt_template"
    LLM_PROMPT_TEMPLATE_VARIABLES = "llm.prompt_template.variables"

    # --- Error Attributes ---
    ERROR_TYPE = "error.type"
    ERROR_MESSAGE = "error.message"
    EXCEPTION_TYPE = "exception.type"
    EXCEPTION_MESSAGE = "exception.message"

    @staticmethod
    def get_span_kind_for_observation_type(obs_type: str) -> str:
        """Map Langfuse observation type to OpenInference span kind.

        Args:
            obs_type: Langfuse observation type ("trace", "generation", "span")

        Returns:
            OpenInference span kind value
        """
        mapping = {
            "trace": LangfuseAttributes.KIND_CHAIN,
            "generation": LangfuseAttributes.KIND_LLM,
            "span": LangfuseAttributes.KIND_CHAIN,
            "tool": LangfuseAttributes.KIND_TOOL,
            "event": LangfuseAttributes.KIND_CHAIN,
        }
        return mapping.get(obs_type.lower(), LangfuseAttributes.KIND_CHAIN)

    @staticmethod
    def build_usage_details(
        input_tokens: int = 0,
        output_tokens: int = 0,
        cache_read_tokens: int = 0,
        cache_creation_tokens: int = 0,
        reasoning_tokens: int = 0,
    ) -> dict:
        """Build a usage_details JSON object for Langfuse.

        Langfuse accepts detailed token breakdown via langfuse.observation.usage_details.

        Args:
            input_tokens: Input/prompt tokens
            output_tokens: Output/completion tokens
            cache_read_tokens: Tokens read from cache
            cache_creation_tokens: Tokens written to cache
            reasoning_tokens: Tokens used for reasoning (o1 models)

        Returns:
            Dictionary suitable for JSON serialization
        """
        details = {
            "input": input_tokens,
            "output": output_tokens,
            "total": input_tokens + output_tokens,
        }
        if cache_read_tokens > 0:
            details["cache_read"] = cache_read_tokens
        if cache_creation_tokens > 0:
            details["cache_creation"] = cache_creation_tokens
        if reasoning_tokens > 0:
            details["reasoning"] = reasoning_tokens
        return details

    @staticmethod
    def build_cost_details(
        input_cost: float = 0.0,
        output_cost: float = 0.0,
        cache_read_cost: float = 0.0,
        cache_creation_cost: float = 0.0,
        total_cost: float = 0.0,
    ) -> dict:
        """Build a cost_details JSON object for Langfuse.

        Args:
            input_cost: Cost for input tokens (USD)
            output_cost: Cost for output tokens (USD)
            cache_read_cost: Cost for cache read tokens (USD)
            cache_creation_cost: Cost for cache creation tokens (USD)
            total_cost: Total cost (USD), or sum if not provided

        Returns:
            Dictionary suitable for JSON serialization
        """
        calculated_total = input_cost + output_cost + cache_read_cost + cache_creation_cost
        return {
            "input": round(input_cost, 8),
            "output": round(output_cost, 8),
            "total": round(total_cost if total_cost > 0 else calculated_total, 8),
        }
