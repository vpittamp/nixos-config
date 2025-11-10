/**
 * Structured Error Model for Sway Test Framework
 *
 * Feature 070 - User Story 1: Clear Error Diagnostics
 * Tasks: T007, T008, T009
 *
 * Provides structured error reporting with diagnostic context and remediation steps
 * for all test framework failures.
 */

import { z } from "zod";

/**
 * Error type enumeration
 * Maps to specific failure scenarios in functional requirements
 */
export enum ErrorType {
  /** App name not found in registry (FR-002) */
  APP_NOT_FOUND = "APP_NOT_FOUND",

  /** PWA name not found in registry (FR-002) */
  PWA_NOT_FOUND = "PWA_NOT_FOUND",

  /** Invalid ULID format provided (FR-013) */
  INVALID_ULID = "INVALID_ULID",

  /** Application or PWA failed to launch (FR-004) */
  LAUNCH_FAILED = "LAUNCH_FAILED",

  /** Action or window wait exceeded timeout (FR-004) */
  TIMEOUT = "TIMEOUT",

  /** Test JSON structure invalid (FR-005) */
  MALFORMED_TEST = "MALFORMED_TEST",

  /** Registry file missing or invalid (FR-025) */
  REGISTRY_ERROR = "REGISTRY_ERROR",

  /** Cleanup operation failed (FR-008, FR-010) */
  CLEANUP_FAILED = "CLEANUP_FAILED",
}

/**
 * Structured error class with diagnostic context
 * Extends Error to provide additional diagnostic information and remediation guidance
 */
export class StructuredError extends Error {
  /** Error category for filtering and reporting */
  public readonly type: ErrorType;

  /** Component that raised the error (e.g., "PWA Launch", "Registry Reader") */
  public readonly component: string;

  /** Root cause description */
  public readonly cause: string;

  /** Ordered list of remediation steps */
  public readonly remediation: string[];

  /** Additional diagnostic context (PIDs, ULIDs, file paths, etc.) */
  public readonly context?: Record<string, unknown>;

  constructor(
    type: ErrorType,
    component: string,
    cause: string,
    remediation: string[],
    context?: Record<string, unknown>
  ) {
    // Construct error message for Error base class
    super(`${component}: ${cause}`);

    this.name = "StructuredError";
    this.type = type;
    this.component = component;
    this.cause = cause;
    this.remediation = remediation;
    this.context = context;

    // Maintain proper stack trace for V8 engines
    if (Error.captureStackTrace) {
      Error.captureStackTrace(this, StructuredError);
    }
  }

  /**
   * Format error as human-readable message
   * @returns Formatted error message with context and remediation steps
   */
  format(): string {
    const lines = [
      `L ${this.type}: ${this.message}`,
      "",
    ];

    // Add context if available
    if (this.context && Object.keys(this.context).length > 0) {
      lines.push("Context:");
      for (const [key, value] of Object.entries(this.context)) {
        const valueStr = typeof value === "string" ? value : JSON.stringify(value);
        lines.push(`  ${key}: ${valueStr}`);
      }
      lines.push("");
    }

    // Add remediation steps
    lines.push("Suggested fixes:");
    this.remediation.forEach((fix, i) => {
      lines.push(`  ${i + 1}. ${fix}`);
    });

    return lines.join("\n");
  }

  /**
   * Convert error to JSON for machine-readable output
   * @returns JSON object representation
   */
  toJSON(): Record<string, unknown> {
    return {
      type: this.type,
      component: this.component,
      cause: this.cause,
      remediation: this.remediation,
      context: this.context || {},
      stack: this.stack,
    };
  }
}

/**
 * Zod schema for StructuredError validation
 * Ensures all required fields are present and valid
 */
export const StructuredErrorSchema = z.object({
  type: z.nativeEnum(ErrorType),
  component: z.string().min(1, "Component must be non-empty"),
  cause: z.string().min(1, "Cause must be non-empty"),
  remediation: z
    .array(z.string().min(1))
    .min(1, "At least one remediation step required"),
  context: z.record(z.unknown()).optional(),
});

/**
 * Type guard to check if an error is a StructuredError
 * @param error - Error to check
 * @returns True if error is StructuredError
 */
export function isStructuredError(error: unknown): error is StructuredError {
  return error instanceof StructuredError;
}

/**
 * Validate StructuredError data against schema
 * @param data - Data to validate
 * @returns Validated StructuredError data
 * @throws {z.ZodError} If validation fails
 */
export function validateStructuredError(
  data: unknown
): z.infer<typeof StructuredErrorSchema> {
  return StructuredErrorSchema.parse(data);
}
