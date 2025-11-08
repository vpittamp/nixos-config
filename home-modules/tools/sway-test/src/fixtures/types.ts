/**
 * Fixture Definition Types (T058 - User Story 5)
 *
 * Defines the format for test fixtures with TypeScript setup/teardown functions.
 */

import type { SwayClient } from "../services/sway-client.ts";

/**
 * Fixture context passed to setup/teardown functions
 */
export interface FixtureContext {
  /** Sway IPC client for executing commands */
  swayClient: SwayClient;

  /** Test name using this fixture */
  testName: string;

  /** Shared state object for passing data between setup/teardown */
  state: Record<string, unknown>;
}

/**
 * Fixture definition with setup/teardown lifecycle
 */
export interface Fixture {
  /** Unique name for this fixture */
  name: string;

  /** Description of what this fixture provides */
  description: string;

  /** Setup function executed before test */
  setup: (context: FixtureContext) => Promise<void>;

  /** Teardown function executed after test */
  teardown: (context: FixtureContext) => Promise<void>;

  /** Optional tags for categorization */
  tags?: string[];
}

/**
 * Result of fixture setup/teardown execution
 */
export interface FixtureExecutionResult {
  /** Fixture that was executed */
  fixture: Fixture;

  /** Success status */
  success: boolean;

  /** Execution duration in milliseconds */
  duration: number;

  /** Error message if failed */
  error?: string;

  /** Final state object after execution */
  state: Record<string, unknown>;
}
