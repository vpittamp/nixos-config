"""
Error handling for Sway Configuration Manager IPC endpoints.

Feature 047 Phase 8 T060: Comprehensive error handling with structured codes
"""

from enum import Enum
from typing import Optional, Dict, Any


class ErrorCode(Enum):
    """
    Error codes for Sway Configuration Manager.

    JSON-RPC standard codes:
    - -32700: Parse error
    - -32600: Invalid request
    - -32601: Method not found
    - -32602: Invalid params
    - -32603: Internal error

    Custom codes (1000-1999):
    - 1000-1099: Validation errors
    - 1100-1199: Configuration errors
    - 1200-1299: File system errors
    - 1300-1399: Git/version control errors
    - 1400-1499: Sway IPC errors
    - 1500-1599: State errors
    """

    # JSON-RPC standard errors
    PARSE_ERROR = -32700
    INVALID_REQUEST = -32600
    METHOD_NOT_FOUND = -32601
    INVALID_PARAMS = -32602
    INTERNAL_ERROR = -32603

    # Validation errors (1000-1099)
    VALIDATION_FAILED = 1000
    SYNTAX_ERROR = 1001
    SEMANTIC_ERROR = 1002
    SCHEMA_ERROR = 1003
    INVALID_REGEX = 1004
    MISSING_REQUIRED_FIELD = 1005

    # Configuration errors (1100-1199)
    CONFIG_LOAD_FAILED = 1100
    CONFIG_MERGE_FAILED = 1101
    CONFIG_APPLY_FAILED = 1102
    CONFIG_CONFLICT = 1103
    INVALID_CONFIG_TYPE = 1104
    PROJECT_NOT_FOUND = 1105
    RULE_NOT_FOUND = 1106

    # File system errors (1200-1299)
    FILE_NOT_FOUND = 1200
    FILE_READ_ERROR = 1201
    FILE_WRITE_ERROR = 1202
    DIRECTORY_NOT_FOUND = 1203
    PERMISSION_DENIED = 1204
    BACKUP_FAILED = 1205

    # Git/version control errors (1300-1399)
    GIT_NOT_INITIALIZED = 1300
    COMMIT_NOT_FOUND = 1301
    ROLLBACK_FAILED = 1302
    GIT_COMMAND_FAILED = 1303
    NO_COMMITS = 1304

    # Sway IPC errors (1400-1499)
    SWAY_NOT_RUNNING = 1400
    SWAY_IPC_FAILED = 1401
    SWAY_RELOAD_FAILED = 1402
    WORKSPACE_NOT_FOUND = 1403
    OUTPUT_NOT_FOUND = 1404

    # State errors (1500-1599)
    DAEMON_NOT_INITIALIZED = 1500
    RELOAD_MANAGER_NOT_READY = 1501
    FILE_WATCHER_NOT_RUNNING = 1502
    CONCURRENT_RELOAD = 1503


class ConfigError(Exception):
    """Base exception for configuration management errors."""

    def __init__(
        self,
        code: ErrorCode,
        message: str,
        suggestion: Optional[str] = None,
        context: Optional[Dict[str, Any]] = None
    ):
        """
        Initialize configuration error.

        Args:
            code: Error code from ErrorCode enum
            message: Human-readable error message
            suggestion: Suggested recovery action
            context: Additional context for debugging
        """
        self.code = code
        self.message = message
        self.suggestion = suggestion
        self.context = context or {}
        super().__init__(message)

    def to_dict(self) -> Dict[str, Any]:
        """
        Convert error to dictionary for JSON-RPC response.

        Returns:
            Error dictionary with code, message, suggestion, and context
        """
        result = {
            "code": self.code.value,
            "message": self.message
        }

        if self.suggestion:
            result["suggestion"] = self.suggestion

        if self.context:
            result["context"] = self.context

        return result


class ValidationError(ConfigError):
    """Validation error with file and line information."""

    def __init__(
        self,
        message: str,
        file_path: Optional[str] = None,
        line_number: Optional[int] = None,
        suggestion: Optional[str] = None
    ):
        """
        Initialize validation error.

        Args:
            message: Error message
            file_path: File where error occurred
            line_number: Line number of error
            suggestion: Suggested fix
        """
        context = {}
        if file_path:
            context["file_path"] = file_path
        if line_number:
            context["line_number"] = line_number

        super().__init__(
            code=ErrorCode.VALIDATION_FAILED,
            message=message,
            suggestion=suggestion,
            context=context
        )


class ConfigLoadError(ConfigError):
    """Configuration loading error."""

    def __init__(self, file_path: str, reason: str):
        """
        Initialize configuration load error.

        Args:
            file_path: Path to configuration file
            reason: Reason for load failure
        """
        super().__init__(
            code=ErrorCode.CONFIG_LOAD_FAILED,
            message=f"Failed to load configuration from {file_path}: {reason}",
            suggestion="Check file syntax and permissions",
            context={"file_path": file_path, "reason": reason}
        )


class GitError(ConfigError):
    """Git operation error."""

    def __init__(self, operation: str, reason: str, suggestion: Optional[str] = None):
        """
        Initialize git error.

        Args:
            operation: Git operation that failed (e.g., "rollback", "commit")
            reason: Reason for failure
            suggestion: Recovery suggestion
        """
        super().__init__(
            code=ErrorCode.GIT_COMMAND_FAILED,
            message=f"Git {operation} failed: {reason}",
            suggestion=suggestion or f"Check git repository state and try again",
            context={"operation": operation, "reason": reason}
        )


class SwayIPCError(ConfigError):
    """Sway IPC communication error."""

    def __init__(self, operation: str, reason: str):
        """
        Initialize Sway IPC error.

        Args:
            operation: IPC operation that failed
            reason: Reason for failure
        """
        super().__init__(
            code=ErrorCode.SWAY_IPC_FAILED,
            message=f"Sway IPC {operation} failed: {reason}",
            suggestion="Ensure Sway is running and IPC socket is accessible",
            context={"operation": operation, "reason": reason}
        )


def error_response(error: Exception, request_id: Optional[Any] = None) -> Dict[str, Any]:
    """
    Create JSON-RPC error response from exception.

    Args:
        error: Exception to convert
        request_id: JSON-RPC request ID

    Returns:
        JSON-RPC error response dictionary
    """
    if isinstance(error, ConfigError):
        error_dict = error.to_dict()
    else:
        # Generic error
        error_dict = {
            "code": ErrorCode.INTERNAL_ERROR.value,
            "message": str(error),
            "suggestion": "Check daemon logs for details"
        }

    return {
        "jsonrpc": "2.0",
        "error": error_dict,
        "id": request_id
    }


def validate_params(params: Dict[str, Any], required: list, optional: Optional[list] = None) -> None:
    """
    Validate request parameters.

    Args:
        params: Request parameters dictionary
        required: List of required parameter names
        optional: List of optional parameter names

    Raises:
        ConfigError: If required parameters are missing or unknown parameters provided
    """
    # Check required parameters
    missing = [key for key in required if key not in params]
    if missing:
        raise ConfigError(
            code=ErrorCode.INVALID_PARAMS,
            message=f"Missing required parameters: {', '.join(missing)}",
            suggestion=f"Provide required parameters: {', '.join(missing)}",
            context={"missing": missing, "required": required}
        )

    # Check for unknown parameters
    if optional is not None:
        allowed = set(required + optional)
        unknown = [key for key in params.keys() if key not in allowed]
        if unknown:
            raise ConfigError(
                code=ErrorCode.INVALID_PARAMS,
                message=f"Unknown parameters: {', '.join(unknown)}",
                suggestion=f"Remove unknown parameters or check API documentation",
                context={"unknown": unknown, "allowed": list(allowed)}
            )
