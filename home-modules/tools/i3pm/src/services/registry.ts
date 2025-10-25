/**
 * Registry service
 * Feature 035: Registry-Centric Project & Workspace Management
 *
 * Loads and parses the application registry from ~/.config/i3/application-registry.json
 */

import { ApplicationRegistry, isApplicationRegistry, RegistryApplication } from "../models/registry.ts";
import * as path from "@std/path";

export class RegistryError extends Error {
  constructor(message: string, public override cause?: Error) {
    super(message);
    this.name = "RegistryError";
  }
}

/**
 * Registry service for loading and querying applications
 */
export class RegistryService {
  private static instance: RegistryService | null = null;
  private registry: ApplicationRegistry | null = null;
  private registryPath: string;

  private constructor(registryPath?: string) {
    const home = Deno.env.get("HOME") || "/home/user";
    this.registryPath = registryPath || path.join(home, ".config/i3/application-registry.json");
  }

  /**
   * Get singleton instance
   */
  static getInstance(registryPath?: string): RegistryService {
    if (!RegistryService.instance) {
      RegistryService.instance = new RegistryService(registryPath);
    }
    return RegistryService.instance;
  }

  /**
   * Load registry from disk
   */
  async load(): Promise<ApplicationRegistry> {
    try {
      const content = await Deno.readTextFile(this.registryPath);
      const data = JSON.parse(content);

      if (!isApplicationRegistry(data)) {
        throw new RegistryError("Invalid registry format");
      }

      this.registry = data;
      return data;
    } catch (error) {
      if (error instanceof Deno.errors.NotFound) {
        throw new RegistryError(
          `Registry not found at ${this.registryPath}. Run 'nixos-rebuild switch' to generate it.`,
          error,
        );
      }
      if (error instanceof SyntaxError) {
        throw new RegistryError(`Invalid JSON in registry: ${error.message}`, error);
      }
      throw error;
    }
  }

  /**
   * Get cached registry or load if not cached
   */
  async getRegistry(): Promise<ApplicationRegistry> {
    if (!this.registry) {
      await this.load();
    }
    return this.registry!;
  }

  /**
   * Find application by name
   */
  async findByName(name: string): Promise<RegistryApplication | null> {
    const registry = await this.getRegistry();
    return registry.applications.find((app) => app.name === name) || null;
  }

  /**
   * List all applications
   */
  async list(): Promise<RegistryApplication[]> {
    const registry = await this.getRegistry();
    return registry.applications;
  }

  /**
   * Filter applications by scope
   */
  async filterByScope(scope: "scoped" | "global"): Promise<RegistryApplication[]> {
    const apps = await this.list();
    return apps.filter((app) => app.scope === scope);
  }

  /**
   * Filter applications by workspace
   */
  async filterByWorkspace(workspace: number): Promise<RegistryApplication[]> {
    const apps = await this.list();
    return apps.filter((app) => app.preferred_workspace === workspace);
  }

  /**
   * Get all scoped applications (for project use)
   */
  async getScopedApps(): Promise<RegistryApplication[]> {
    return this.filterByScope("scoped");
  }

  /**
   * Get all global applications
   */
  async getGlobalApps(): Promise<RegistryApplication[]> {
    return this.filterByScope("global");
  }

  /**
   * Validate application exists in registry
   */
  async exists(name: string): Promise<boolean> {
    const app = await this.findByName(name);
    return app !== null;
  }

  /**
   * Reload registry from disk (clear cache)
   */
  async reload(): Promise<ApplicationRegistry> {
    this.registry = null;
    return await this.load();
  }

  /**
   * Get registry file path
   */
  getPath(): string {
    return this.registryPath;
  }
}
