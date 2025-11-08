/**
 * Fixture Manager Service (T057 - User Story 5)
 *
 * Manages test fixture lifecycle: loading, setup, teardown, and state management.
 */

import type {
  Fixture,
  FixtureContext,
  FixtureExecutionResult,
} from "./types.ts";
import { SwayClient } from "../services/sway-client.ts";

/**
 * Options for FixtureManager
 */
export interface FixtureManagerOptions {
  swayClient?: SwayClient;
  fixturesPath?: string; // Path to fixtures directory
}

/**
 * Service for managing test fixtures
 */
export class FixtureManager {
  private swayClient: SwayClient;
  private fixturesPath: string;
  private loadedFixtures: Map<string, Fixture> = new Map();
  private fixtureStates: Map<string, Record<string, unknown>> = new Map();

  constructor(options: FixtureManagerOptions = {}) {
    this.swayClient = options.swayClient || new SwayClient();
    this.fixturesPath = options.fixturesPath ||
      "./src/fixtures";
  }

  /**
   * Load a fixture by name from file
   */
  async loadFixture(name: string): Promise<Fixture> {
    // Check if already loaded
    if (this.loadedFixtures.has(name)) {
      return this.loadedFixtures.get(name)!;
    }

    // Load fixture module dynamically
    const fixturePath = `${this.fixturesPath}/${name}.ts`;

    try {
      const module = await import(fixturePath);

      if (!module.default) {
        throw new Error(`Fixture ${name} must export a default Fixture object`);
      }

      const fixture: Fixture = module.default;

      // Validate fixture structure
      this.validateFixture(fixture);

      // Cache loaded fixture
      this.loadedFixtures.set(name, fixture);

      return fixture;
    } catch (error) {
      const err = error as Error;
      throw new Error(`Failed to load fixture ${name}: ${err.message}`);
    }
  }

  /**
   * Load multiple fixtures by name
   */
  async loadFixtures(names: string[]): Promise<Fixture[]> {
    const fixtures: Fixture[] = [];

    for (const name of names) {
      const fixture = await this.loadFixture(name);
      fixtures.push(fixture);
    }

    return fixtures;
  }

  /**
   * Execute fixture setup
   */
  async setup(
    fixture: Fixture,
    testName: string,
  ): Promise<FixtureExecutionResult> {
    const startTime = performance.now();

    // Initialize state for this fixture+test combination
    const stateKey = `${fixture.name}:${testName}`;
    const state: Record<string, unknown> = {};
    this.fixtureStates.set(stateKey, state);

    // Build context
    const context: FixtureContext = {
      swayClient: this.swayClient,
      testName,
      state,
    };

    try {
      // Execute setup
      await fixture.setup(context);

      const duration = Math.round(performance.now() - startTime);

      return {
        fixture,
        success: true,
        duration,
        state,
      };
    } catch (error) {
      const duration = Math.round(performance.now() - startTime);
      const err = error as Error;

      return {
        fixture,
        success: false,
        duration,
        error: err.message,
        state,
      };
    }
  }

  /**
   * Execute fixture teardown
   */
  async teardown(
    fixture: Fixture,
    testName: string,
  ): Promise<FixtureExecutionResult> {
    const startTime = performance.now();

    // Retrieve state for this fixture+test combination
    const stateKey = `${fixture.name}:${testName}`;
    const state = this.fixtureStates.get(stateKey) || {};

    // Build context
    const context: FixtureContext = {
      swayClient: this.swayClient,
      testName,
      state,
    };

    try {
      // Execute teardown
      await fixture.teardown(context);

      // Clean up state
      this.fixtureStates.delete(stateKey);

      const duration = Math.round(performance.now() - startTime);

      return {
        fixture,
        success: true,
        duration,
        state,
      };
    } catch (error) {
      const duration = Math.round(performance.now() - startTime);
      const err = error as Error;

      return {
        fixture,
        success: false,
        duration,
        error: err.message,
        state,
      };
    }
  }

  /**
   * Setup multiple fixtures in order
   */
  async setupAll(
    fixtures: Fixture[],
    testName: string,
  ): Promise<FixtureExecutionResult[]> {
    const results: FixtureExecutionResult[] = [];

    for (const fixture of fixtures) {
      const result = await this.setup(fixture, testName);
      results.push(result);

      // Stop on first failure
      if (!result.success) {
        throw new Error(
          `Fixture setup failed for ${fixture.name}: ${result.error}`,
        );
      }
    }

    return results;
  }

  /**
   * Teardown multiple fixtures in reverse order
   */
  async teardownAll(
    fixtures: Fixture[],
    testName: string,
  ): Promise<FixtureExecutionResult[]> {
    const results: FixtureExecutionResult[] = [];

    // Teardown in reverse order (LIFO)
    const reversedFixtures = [...fixtures].reverse();

    for (const fixture of reversedFixtures) {
      const result = await this.teardown(fixture, testName);
      results.push(result);

      // Continue even on failure to ensure cleanup
      if (!result.success) {
        console.warn(
          `Fixture teardown failed for ${fixture.name}: ${result.error}`,
        );
      }
    }

    return results;
  }

  /**
   * Get fixture state for a test
   */
  getFixtureState(
    fixtureName: string,
    testName: string,
  ): Record<string, unknown> | undefined {
    const stateKey = `${fixtureName}:${testName}`;
    return this.fixtureStates.get(stateKey);
  }

  /**
   * Validate fixture structure
   */
  private validateFixture(fixture: Fixture): void {
    if (!fixture.name) {
      throw new Error("Fixture must have a name");
    }

    if (!fixture.description) {
      throw new Error("Fixture must have a description");
    }

    if (typeof fixture.setup !== "function") {
      throw new Error("Fixture must have a setup function");
    }

    if (typeof fixture.teardown !== "function") {
      throw new Error("Fixture must have a teardown function");
    }
  }

  /**
   * Clear all loaded fixtures and states
   */
  clear(): void {
    this.loadedFixtures.clear();
    this.fixtureStates.clear();
  }
}
