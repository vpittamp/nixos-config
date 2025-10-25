/**
 * Project manager service
 * Feature 035: Registry-Centric Project & Workspace Management
 *
 * CRUD operations for projects: create, read, update, delete, list
 * NO APPLICATION_TAGS - environment-based filtering only
 */

import {
  ActiveProject,
  CreateProjectParams,
  isActiveProject,
  isProject,
  isValidDirectory,
  isValidProjectName,
  Project,
  UpdateProjectParams,
} from "../models/project.ts";
import * as path from "@std/path";
import { exists } from "@std/fs";

export class ProjectError extends Error {
  constructor(message: string, public cause?: Error) {
    super(message);
    this.name = "ProjectError";
  }
}

/**
 * Project manager service for project CRUD operations
 */
export class ProjectManager {
  private projectsDir: string;
  private activeProjectPath: string;

  constructor(configDir?: string) {
    const home = Deno.env.get("HOME") || "/home/user";
    const baseDir = configDir || path.join(home, ".config/i3");
    this.projectsDir = path.join(baseDir, "projects");
    this.activeProjectPath = path.join(baseDir, "active-project.json");
  }

  /**
   * Ensure projects directory exists
   */
  private async ensureProjectsDir(): Promise<void> {
    await Deno.mkdir(this.projectsDir, { recursive: true });
  }

  /**
   * Get project file path
   */
  private getProjectPath(name: string): string {
    return path.join(this.projectsDir, `${name}.json`);
  }

  /**
   * Validate project name format
   */
  private validateName(name: string): void {
    if (!isValidProjectName(name)) {
      throw new ProjectError(
        `Invalid project name '${name}'. Must be kebab-case, 3-64 characters.`,
      );
    }
  }

  /**
   * Validate directory exists and is absolute
   */
  private async validateDirectory(directory: string): Promise<void> {
    if (!isValidDirectory(directory)) {
      throw new ProjectError(
        `Invalid directory '${directory}'. Must be an absolute path (starts with / or ~).`,
      );
    }

    // Expand ~ to home directory
    const expandedDir = directory.startsWith("~")
      ? directory.replace("~", Deno.env.get("HOME") || "/home/user")
      : directory;

    try {
      const stat = await Deno.stat(expandedDir);
      if (!stat.isDirectory) {
        throw new ProjectError(`Path '${directory}' exists but is not a directory.`);
      }
    } catch (error) {
      if (error instanceof Deno.errors.NotFound) {
        throw new ProjectError(
          `Directory '${directory}' does not exist. Create it first.`,
          error,
        );
      }
      throw error;
    }
  }

  /**
   * Create a new project
   */
  async create(params: CreateProjectParams): Promise<Project> {
    this.validateName(params.name);
    await this.validateDirectory(params.directory);
    await this.ensureProjectsDir();

    const projectPath = this.getProjectPath(params.name);

    // Check if project already exists
    if (await exists(projectPath)) {
      throw new ProjectError(`Project '${params.name}' already exists.`);
    }

    const now = new Date().toISOString();
    const project: Project = {
      name: params.name,
      display_name: params.display_name,
      directory: params.directory,
      icon: params.icon,
      created_at: now,
      updated_at: now,
    };

    await Deno.writeTextFile(projectPath, JSON.stringify(project, null, 2));
    return project;
  }

  /**
   * Load project by name
   */
  async load(name: string): Promise<Project> {
    this.validateName(name);
    const projectPath = this.getProjectPath(name);

    try {
      const content = await Deno.readTextFile(projectPath);
      const data = JSON.parse(content);

      if (!isProject(data)) {
        throw new ProjectError(`Invalid project format in ${projectPath}`);
      }

      return data;
    } catch (error) {
      if (error instanceof Deno.errors.NotFound) {
        throw new ProjectError(`Project '${name}' not found.`, error);
      }
      if (error instanceof SyntaxError) {
        throw new ProjectError(`Invalid JSON in project '${name}': ${error.message}`, error);
      }
      throw error;
    }
  }

  /**
   * Update project
   */
  async update(name: string, params: UpdateProjectParams): Promise<Project> {
    const project = await this.load(name);

    if (params.directory) {
      await this.validateDirectory(params.directory);
    }

    const updated: Project = {
      ...project,
      display_name: params.display_name ?? project.display_name,
      directory: params.directory ?? project.directory,
      icon: params.icon ?? project.icon,
      saved_layout: params.saved_layout ?? project.saved_layout,
      updated_at: new Date().toISOString(),
    };

    const projectPath = this.getProjectPath(name);
    await Deno.writeTextFile(projectPath, JSON.stringify(updated, null, 2));
    return updated;
  }

  /**
   * Delete project
   */
  async delete(name: string): Promise<void> {
    this.validateName(name);
    const projectPath = this.getProjectPath(name);

    try {
      await Deno.remove(projectPath);
    } catch (error) {
      if (error instanceof Deno.errors.NotFound) {
        throw new ProjectError(`Project '${name}' not found.`, error);
      }
      throw error;
    }

    // Clear active project if it was deleted
    const active = await this.getActive();
    if (active.project_name === name) {
      await this.clearActive();
    }
  }

  /**
   * List all projects
   */
  async list(): Promise<Project[]> {
    await this.ensureProjectsDir();

    const projects: Project[] = [];
    for await (const entry of Deno.readDir(this.projectsDir)) {
      if (entry.isFile && entry.name.endsWith(".json")) {
        const name = entry.name.replace(".json", "");
        try {
          const project = await this.load(name);
          projects.push(project);
        } catch (error) {
          console.warn(`Failed to load project ${name}:`, error);
        }
      }
    }

    return projects.sort((a, b) => a.name.localeCompare(b.name));
  }

  /**
   * Check if project exists
   */
  async exists(name: string): Promise<boolean> {
    this.validateName(name);
    const projectPath = this.getProjectPath(name);
    return await exists(projectPath);
  }

  /**
   * Get active project state
   */
  async getActive(): Promise<ActiveProject> {
    try {
      const content = await Deno.readTextFile(this.activeProjectPath);
      const data = JSON.parse(content);

      if (!isActiveProject(data)) {
        return { project_name: null, activated_at: null };
      }

      return data;
    } catch (error) {
      if (error instanceof Deno.errors.NotFound) {
        return { project_name: null, activated_at: null };
      }
      throw error;
    }
  }

  /**
   * Set active project
   */
  async setActive(projectName: string): Promise<void> {
    // Validate project exists
    await this.load(projectName);

    const active: ActiveProject = {
      project_name: projectName,
      activated_at: new Date().toISOString(),
    };

    await Deno.writeTextFile(this.activeProjectPath, JSON.stringify(active, null, 2));
  }

  /**
   * Clear active project (return to global mode)
   */
  async clearActive(): Promise<void> {
    const active: ActiveProject = {
      project_name: null,
      activated_at: null,
    };

    await Deno.writeTextFile(this.activeProjectPath, JSON.stringify(active, null, 2));
  }

  /**
   * Get current active project (returns Project or null)
   */
  async getCurrent(): Promise<Project | null> {
    const active = await this.getActive();
    if (!active.project_name) {
      return null;
    }

    try {
      return await this.load(active.project_name);
    } catch (error) {
      console.warn(`Active project '${active.project_name}' not found, clearing:`, error);
      await this.clearActive();
      return null;
    }
  }
}
