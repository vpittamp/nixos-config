/**
 * Validate Command Handler
 *
 * Validates test definition JSON files against the schema using Zod.
 */

import { z } from "zod";

/**
 * Action type schema
 */
const ActionTypeSchema = z.enum([
  "launch_app",
  "send_ipc",
  "switch_workspace",
  "focus_window",
  "wait_event",
  "debug_pause",
  "await_sync",
]);

/**
 * Action schema
 */
const ActionSchema = z.object({
  type: ActionTypeSchema,
  params: z.record(z.unknown()).optional(),
  description: z.string().optional(),
});

/**
 * Action sequence schema
 */
const ActionSequenceSchema = z.array(ActionSchema);

/**
 * Expected state schema
 */
const ExpectedStateSchema = z.object({
  state: z.unknown(), // StateSnapshot or partial match
  mode: z.enum(["exact", "partial"]).optional(),
  description: z.string().optional(),
});

/**
 * Test case schema
 */
const TestCaseSchema = z.object({
  name: z.string().min(1, "Test name is required"),
  description: z.string().optional(),
  tags: z.array(z.string()).optional(),
  priority: z.enum(["P1", "P2", "P3"]).optional(),
  timeout: z.number().int().positive().optional(),
  setup: ActionSequenceSchema.optional(),
  actions: ActionSequenceSchema,
  teardown: ActionSequenceSchema.optional(),
  expectedState: ExpectedStateSchema,
  fixtures: z.array(z.string()).optional(),
  config: z.record(z.unknown()).optional(),
});

/**
 * Test suite schema (array of test cases)
 */
const TestSuiteSchema = z.union([
  TestCaseSchema,
  z.array(TestCaseSchema),
]);

/**
 * Validation result
 */
export interface ValidationResult {
  valid: boolean;
  errors: string[];
  warnings: string[];
}

/**
 * Validate test definition file
 */
export async function validateTestFile(filePath: string): Promise<ValidationResult> {
  const result: ValidationResult = {
    valid: true,
    errors: [],
    warnings: [],
  };

  try {
    // Read file
    const content = await Deno.readTextFile(filePath);

    // Parse JSON
    let json: unknown;
    try {
      json = JSON.parse(content);
    } catch (error) {
      result.valid = false;
      result.errors.push(`Invalid JSON: ${error.message}`);
      return result;
    }

    // Validate against schema
    const parseResult = TestSuiteSchema.safeParse(json);

    if (!parseResult.success) {
      result.valid = false;

      // Extract Zod errors
      for (const issue of parseResult.error.issues) {
        const path = issue.path.join(".");
        result.errors.push(`${path || "root"}: ${issue.message}`);
      }
    } else {
      // Additional semantic validation
      const testCases = Array.isArray(parseResult.data)
        ? parseResult.data
        : [parseResult.data];

      for (const testCase of testCases) {
        // Warn if no actions
        if (!testCase.actions || testCase.actions.length === 0) {
          result.warnings.push(
            `Test "${testCase.name}": No actions defined - test will only capture current state`,
          );
        }

        // Warn if timeout is very long
        if (testCase.timeout && testCase.timeout > 60000) {
          result.warnings.push(
            `Test "${testCase.name}": Timeout ${testCase.timeout}ms is very long (>60s)`,
          );
        }

        // Warn if no priority set
        if (!testCase.priority) {
          result.warnings.push(
            `Test "${testCase.name}": No priority set (defaults to P2)`,
          );
        }
      }
    }
  } catch (error) {
    result.valid = false;
    result.errors.push(`Failed to read file: ${error.message}`);
  }

  return result;
}

/**
 * Validate command entry point
 */
export async function validateCommand(files: string[]): Promise<number> {
  if (files.length === 0) {
    console.error("Error: No files specified");
    return 1;
  }

  let hasErrors = false;

  for (const file of files) {
    console.log(`Validating ${file}...`);

    const result = await validateTestFile(file);

    if (result.valid) {
      console.log("  ✓ Valid");
    } else {
      console.log("  ✗ Invalid");
      hasErrors = true;
    }

    // Print errors
    if (result.errors.length > 0) {
      console.log("\n  Errors:");
      for (const error of result.errors) {
        console.log(`    - ${error}`);
      }
    }

    // Print warnings
    if (result.warnings.length > 0) {
      console.log("\n  Warnings:");
      for (const warning of result.warnings) {
        console.log(`    - ${warning}`);
      }
    }

    console.log("");
  }

  return hasErrors ? 1 : 0;
}
