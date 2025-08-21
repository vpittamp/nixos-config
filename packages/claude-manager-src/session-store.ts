/**
 * Session Store - Local caching for Claude sessions
 * 
 * Uses Deno KV for fast local storage and caching of session metadata.
 * Provides quick access to frequently used sessions and maintains
 * sync with filesystem-based session files.
 */

import type { ClaudeSession, SessionFileEntry } from "./claude-types.ts";
import { join } from "@std/path";

/**
 * Session cache entry with additional metadata
 */
interface CachedSession extends ClaudeSession {
  lastAccessed: Date;
  accessCount: number;
  favorite: boolean;
  tags: string[];
  filePath: string;
}

/**
 * Session store configuration
 */
interface StoreConfig {
  maxCacheSize: number;
  cacheExpiry: number; // milliseconds
  autoSync: boolean;
  syncInterval: number; // milliseconds
}

/**
 * Session Store class using Deno KV
 */
export class SessionStore {
  private kv: Deno.Kv | null = null;
  private config: StoreConfig;
  private syncTimer: number | null = null;
  
  constructor(config: Partial<StoreConfig> = {}) {
    this.config = {
      maxCacheSize: config.maxCacheSize || 100,
      cacheExpiry: config.cacheExpiry || 24 * 60 * 60 * 1000, // 24 hours
      autoSync: config.autoSync ?? true,
      syncInterval: config.syncInterval || 5 * 60 * 1000, // 5 minutes
    };
  }
  
  /**
   * Initialize the KV store
   */
  async init(): Promise<void> {
    const dbPath = join(Deno.env.get("HOME") || "", ".claude", "session-cache.db");
    this.kv = await Deno.openKv(dbPath);
    
    if (this.config.autoSync) {
      await this.startAutoSync();
    }
    
    console.log("✅ Session store initialized");
  }
  
  /**
   * Close the store
   */
  async close(): Promise<void> {
    if (this.syncTimer) {
      clearInterval(this.syncTimer);
    }
    
    if (this.kv) {
      this.kv.close();
      this.kv = null;
    }
  }
  
  /**
   * Get a session from cache
   */
  async get(sessionId: string): Promise<CachedSession | null> {
    if (!this.kv) throw new Error("Store not initialized");
    
    const entry = await this.kv.get<CachedSession>(["sessions", sessionId]);
    
    if (entry.value) {
      // Update access metadata
      const updated: CachedSession = {
        ...entry.value,
        lastAccessed: new Date(),
        accessCount: (entry.value.accessCount || 0) + 1,
      };
      
      await this.kv.set(["sessions", sessionId], updated);
      return updated;
    }
    
    return null;
  }
  
  /**
   * Store a session in cache
   */
  async set(session: ClaudeSession, filePath: string): Promise<void> {
    if (!this.kv) throw new Error("Store not initialized");
    
    const cached: CachedSession = {
      ...session,
      lastAccessed: new Date(),
      accessCount: 0,
      favorite: false,
      tags: [],
      filePath,
    };
    
    await this.kv.set(["sessions", session.id], cached);
    
    // Update index entries
    await this.updateIndices(cached);
  }
  
  /**
   * Update multiple indices for quick lookups
   */
  private async updateIndices(session: CachedSession): Promise<void> {
    if (!this.kv) return;
    
    // Index by directory
    await this.kv.set(["by-dir", session.cwd, session.id], session.id);
    
    // Index by project (derived from path)
    const project = this.getProjectName(session.cwd);
    await this.kv.set(["by-project", project, session.id], session.id);
    
    // Index by date
    const dateKey = new Date(session.timestamp).toISOString().split("T")[0];
    await this.kv.set(["by-date", dateKey, session.id], session.id);
    
    // Index favorites
    if (session.favorite) {
      await this.kv.set(["favorites", session.id], session.id);
    }
    
    // Index by tags
    for (const tag of session.tags) {
      await this.kv.set(["by-tag", tag, session.id], session.id);
    }
  }
  
  /**
   * Get project name from path
   */
  private getProjectName(path: string): string {
    const parts = path.split("/");
    
    // Check for common project patterns
    if (path.includes("/projects/")) {
      const idx = parts.indexOf("projects");
      return parts[idx + 1] || "unknown";
    }
    
    if (path.includes("/home/") && parts.length > 3) {
      return parts[3] || "home";
    }
    
    return parts[parts.length - 1] || "unknown";
  }
  
  /**
   * List all cached sessions
   */
  async list(options: {
    limit?: number;
    offset?: number;
    sortBy?: "date" | "accessed" | "name";
    filter?: {
      project?: string;
      directory?: string;
      tag?: string;
      favorite?: boolean;
    };
  } = {}): Promise<CachedSession[]> {
    if (!this.kv) throw new Error("Store not initialized");
    
    const sessions: CachedSession[] = [];
    const limit = options.limit || 50;
    const offset = options.offset || 0;
    
    // Apply filters
    let prefix: Deno.KvKey = ["sessions"];
    if (options.filter?.project) {
      prefix = ["by-project", options.filter.project];
    } else if (options.filter?.directory) {
      prefix = ["by-dir", options.filter.directory];
    } else if (options.filter?.tag) {
      prefix = ["by-tag", options.filter.tag];
    } else if (options.filter?.favorite) {
      prefix = ["favorites"];
    }
    
    // Fetch sessions
    const iter = this.kv.list<CachedSession>({ prefix });
    let count = 0;
    
    for await (const entry of iter) {
      if (count >= offset && sessions.length < limit) {
        if (prefix[0] === "sessions") {
          sessions.push(entry.value);
        } else {
          // For index entries, fetch the actual session
          const sessionId = entry.value as unknown as string;
          const session = await this.get(sessionId);
          if (session) sessions.push(session);
        }
      }
      count++;
    }
    
    // Sort results
    if (options.sortBy === "date") {
      sessions.sort((a, b) => 
        new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime()
      );
    } else if (options.sortBy === "accessed") {
      sessions.sort((a, b) => 
        b.lastAccessed.getTime() - a.lastAccessed.getTime()
      );
    } else if (options.sortBy === "name") {
      sessions.sort((a, b) => a.cwd.localeCompare(b.cwd));
    }
    
    return sessions;
  }
  
  /**
   * Search sessions by text
   */
  async search(query: string): Promise<CachedSession[]> {
    if (!this.kv) throw new Error("Store not initialized");
    
    const results: CachedSession[] = [];
    const searchLower = query.toLowerCase();
    
    const iter = this.kv.list<CachedSession>({ prefix: ["sessions"] });
    
    for await (const entry of iter) {
      const session = entry.value;
      
      // Search in multiple fields
      const searchFields = [
        session.cwd,
        session.summary || "",
        session.lastMessage || "",
        session.gitBranch || "",
        ...session.tags,
      ];
      
      const matches = searchFields.some(field => 
        field.toLowerCase().includes(searchLower)
      );
      
      if (matches) {
        results.push(session);
      }
    }
    
    return results;
  }
  
  /**
   * Mark session as favorite
   */
  async toggleFavorite(sessionId: string): Promise<boolean> {
    const session = await this.get(sessionId);
    if (!session) return false;
    
    session.favorite = !session.favorite;
    await this.kv!.set(["sessions", sessionId], session);
    
    if (session.favorite) {
      await this.kv!.set(["favorites", sessionId], sessionId);
    } else {
      await this.kv!.delete(["favorites", sessionId]);
    }
    
    return session.favorite;
  }
  
  /**
   * Add tags to a session
   */
  async addTags(sessionId: string, tags: string[]): Promise<void> {
    const session = await this.get(sessionId);
    if (!session) return;
    
    // Add new tags
    const newTags = new Set([...session.tags, ...tags]);
    session.tags = Array.from(newTags);
    
    await this.kv!.set(["sessions", sessionId], session);
    await this.updateIndices(session);
  }
  
  /**
   * Get frequently accessed sessions
   */
  async getFrequent(limit = 10): Promise<CachedSession[]> {
    const sessions = await this.list({ limit: 100 });
    
    return sessions
      .sort((a, b) => b.accessCount - a.accessCount)
      .slice(0, limit);
  }
  
  /**
   * Get recent sessions
   */
  async getRecent(limit = 10): Promise<CachedSession[]> {
    return this.list({ 
      limit, 
      sortBy: "accessed" 
    });
  }
  
  /**
   * Sync with filesystem
   */
  async syncWithFilesystem(): Promise<void> {
    const homeDir = Deno.env.get("HOME") || "";
    const projectsDir = join(homeDir, ".claude", "projects");
    
    console.log("🔄 Syncing with filesystem...");
    
    try {
      // Walk through all JSONL files
      for await (const entry of Deno.readDir(projectsDir)) {
        if (entry.isDirectory) {
          const subDir = join(projectsDir, entry.name);
          
          for await (const file of Deno.readDir(subDir)) {
            if (file.name.endsWith(".jsonl")) {
              const filePath = join(subDir, file.name);
              const session = await this.parseSessionFile(filePath);
              
              if (session) {
                // Check if already cached
                const cached = await this.get(session.id);
                
                // Update if newer or not cached
                if (!cached || new Date(session.timestamp) > new Date(cached.timestamp)) {
                  await this.set(session, filePath);
                }
              }
            }
          }
        }
      }
      
      console.log("✅ Sync complete");
    } catch (error) {
      console.error("❌ Sync failed:", error);
    }
  }
  
  /**
   * Parse session file
   */
  private async parseSessionFile(filePath: string): Promise<ClaudeSession | null> {
    try {
      const content = await Deno.readTextFile(filePath);
      const lines = content.split("\n").filter(line => line.trim());
      
      if (lines.length === 0) return null;
      
      const filename = filePath.split("/").pop() || "";
      const sessionId = filename.replace(".jsonl", "");
      
      let messageCount = 0;
      let lastMessage = "";
      let summary = "";
      let cwd = "";
      let gitBranch = "";
      let timestamp = "";
      
      for (const line of lines) {
        try {
          const entry = JSON.parse(line) as SessionFileEntry;
          
          if (!timestamp && entry.timestamp) {
            timestamp = entry.timestamp;
          }
          
          if (entry.cwd) cwd = entry.cwd;
          if (entry.gitBranch) gitBranch = entry.gitBranch;
          
          if (entry.type === "message") {
            messageCount++;
            if (entry.message?.role === "user") {
              const content = entry.message.content;
              lastMessage = typeof content === "string" 
                ? content 
                : content[0]?.text || "";
            }
          } else if (entry.type === "summary") {
            summary = entry.summary || "";
          }
        } catch {
          // Skip malformed lines
        }
      }
      
      return {
        id: sessionId,
        timestamp: timestamp || new Date().toISOString(),
        cwd: cwd || process.cwd(),
        gitBranch,
        status: "completed",
        messageCount,
        lastMessage: lastMessage.slice(0, 100),
        summary,
      };
    } catch {
      return null;
    }
  }
  
  /**
   * Start auto-sync timer
   */
  private async startAutoSync(): Promise<void> {
    // Initial sync
    await this.syncWithFilesystem();
    
    // Set up periodic sync
    this.syncTimer = setInterval(async () => {
      await this.syncWithFilesystem();
    }, this.config.syncInterval);
  }
  
  /**
   * Get statistics
   */
  async getStats(): Promise<{
    totalSessions: number;
    favoriteCount: number;
    tagCount: number;
    projectCount: number;
    recentlyAccessed: number;
  }> {
    if (!this.kv) throw new Error("Store not initialized");
    
    let totalSessions = 0;
    let favoriteCount = 0;
    const tags = new Set<string>();
    const projects = new Set<string>();
    let recentlyAccessed = 0;
    
    const dayAgo = Date.now() - 24 * 60 * 60 * 1000;
    
    const iter = this.kv.list<CachedSession>({ prefix: ["sessions"] });
    
    for await (const entry of iter) {
      const session = entry.value;
      totalSessions++;
      
      if (session.favorite) favoriteCount++;
      
      session.tags.forEach(tag => tags.add(tag));
      projects.add(this.getProjectName(session.cwd));
      
      if (session.lastAccessed.getTime() > dayAgo) {
        recentlyAccessed++;
      }
    }
    
    return {
      totalSessions,
      favoriteCount,
      tagCount: tags.size,
      projectCount: projects.size,
      recentlyAccessed,
    };
  }
}

/**
 * Create and initialize a session store
 */
export async function createSessionStore(
  config?: Partial<StoreConfig>
): Promise<SessionStore> {
  const store = new SessionStore(config);
  await store.init();
  return store;
}