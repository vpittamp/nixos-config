/**
 * Project Manager Service
 * Feature 077: Git Worktree Project Management
 *
 * This service provides high-level project management operations,
 * including support for both regular and worktree-based projects.
 */

import { DaemonClient } from "./daemon-client.ts";
import type { Project } from "../models/project.ts";
import { isWorktreeProject, type WorktreeProject } from "../models/worktree.ts";
import { join } from "@std/path";

// ============================================================================
// ProjectManagerService Class
// ============================================================================

/**
 * Service for managing i3pm projects
 *
 * Provides unified interface for:
 * - Creating regular and worktree projects
 * - Deleting projects
 * - Checking project status
 * - Handling worktree discriminator logic
 */
export class ProjectManagerService {
  /**
   * Create a worktree-based project
   *
   * Creates an i3pm project with worktree metadata, which acts as a
   * discriminator to identify it as a worktree-managed project.
   *
   * @param project - Worktree project configuration
   * @returns Created worktree project
   * @throws Error if project creation fails
   */
  async createWorktreeProject(project: WorktreeProject): Promise<WorktreeProject> {
    // Write project JSON directly to ~/.config/i3/projects/
    // The daemon will pick it up on next reload
    const homeDir = Deno.env.get("HOME") || "/home/vpittamp";
    const projectsDir = join(homeDir, ".config", "i3", "projects");

    // Ensure projects directory exists
    await Deno.mkdir(projectsDir, { recursive: true });

    const projectFile = join(projectsDir, `${project.name}.json`);

    // Write project JSON
    const projectData = {
      name: project.name,
      display_name: project.display_name,
      directory: project.directory,
      icon: project.icon,
      scoped_classes: project.scoped_classes || [],
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      // Include worktree metadata
      worktree: project.worktree,
    };

    await Deno.writeTextFile(projectFile, JSON.stringify(projectData, null, 2));

    return project;
  }

  /**
   * Delete a worktree project
   *
   * Removes the project registration from i3pm.
   * Note: This does NOT delete the git worktree itself - use GitWorktreeService for that.
   *
   * @param projectName - Project name to delete
   * @returns True if deletion successful
   * @throws Error if deletion fails
   */
  async deleteWorktreeProject(projectName: string): Promise<boolean> {
    // Implementation will be added in User Story 4 (Phase 7)
    throw new Error("Not yet implemented");
  }

  /**
   * Check if a project is currently active (being used)
   *
   * @param projectName - Project name to check
   * @returns True if project is currently active
   */
  async isCurrentlyActive(projectName: string): Promise<boolean> {
    // Implementation will be added in User Story 4 (Phase 7)
    throw new Error("Not yet implemented");
  }

  /**
   * Get all projects (both regular and worktree-based)
   *
   * @returns Array of all projects
   */
  async getAllProjects(): Promise<Project[]> {
    const client = new DaemonClient();
    return await client.request<Project[]>("list_projects");
  }

  /**
   * Get only worktree projects
   *
   * @returns Array of worktree projects
   */
  async getWorktreeProjects(): Promise<WorktreeProject[]> {
    const allProjects = await this.getAllProjects();
    return allProjects.filter(isWorktreeProject);
  }

  /**
   * Get a specific project by name
   *
   * @param projectName - Project name
   * @returns Project if found, undefined otherwise
   */
  async getProject(projectName: string): Promise<Project | undefined> {
    const allProjects = await this.getAllProjects();
    return allProjects.find((p) => p.name === projectName);
  }
}
