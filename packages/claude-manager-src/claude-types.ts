/**
 * Claude Code SDK Type Definitions and Interfaces
 * 
 * This module re-exports and extends the Claude Code SDK types
 * for use in our Deno-based session management system.
 */

// Import Claude Code SDK types
// Using npm: specifier for direct npm package import in Deno
import type {
  SDKMessage,
  SDKUserMessage,
  SDKAssistantMessage,
  SDKResultMessage,
  SDKSystemMessage,
  Options as ClaudeCodeOptions,
  PermissionMode,
  HookInput,
  HookJSONOutput,
  Query,
} from "npm:@anthropic-ai/claude-code@1.0.86";

// Re-export core types for convenience
export type {
  SDKMessage,
  SDKUserMessage,
  SDKAssistantMessage,
  SDKResultMessage,
  SDKSystemMessage,
  ClaudeCodeOptions,
  PermissionMode,
  HookInput,
  HookJSONOutput,
  Query,
};

/**
 * Extended session metadata that combines Claude Code SDK types
 * with our custom session management needs
 */
export interface ClaudeSession {
  // Core session info
  id: string;
  timestamp: string;
  cwd: string;
  
  // Git integration
  gitBranch?: string;
  gitStatus?: string;
  
  // Sesh/tmux integration
  seshName?: string;
  tmuxSession?: string;
  tmuxWindow?: string;
  
  // Claude Code specific
  model?: string;
  permissionMode?: PermissionMode;
  apiKeySource?: 'user' | 'project' | 'org' | 'temporary';
  
  // Session state
  status: 'active' | 'paused' | 'completed' | 'error';
  summary?: string;
  messageCount: number;
  lastMessage?: string;
  
  // MCP servers if any
  mcpServers?: Array<{
    name: string;
    status: string;
  }>;
}

/**
 * Session file entry as stored in JSONL format
 */
export interface SessionFileEntry {
  type: 'message' | 'summary' | 'metadata';
  timestamp: string;
  message?: {
    role: 'user' | 'assistant' | 'system';
    content: string | Array<{ text: string; type?: string }>;
  };
  summary?: string;
  cwd?: string;
  gitBranch?: string;
  sessionId?: string;
}

/**
 * Configuration for our Claude session manager
 */
export interface SessionManagerConfig {
  // Paths
  claudeDir: string;
  projectsDir: string;
  
  // UI preferences
  useGum: boolean;
  useFzf: boolean;
  useTmux: boolean;
  
  // Session defaults
  defaultPermissionMode: PermissionMode;
  maxTurns?: number;
  systemPrompt?: string;
  
  // Integration options
  enableZoxide: boolean;
  enableSesh: boolean;
  enableMcp: boolean;
}

/**
 * Command execution result
 */
export interface CommandResult {
  success: boolean;
  stdout: string;
  stderr?: string;
  code: number;
}

/**
 * Session selection result
 */
export interface SessionSelection {
  session: ClaudeSession;
  action: 'resume' | 'view' | 'export' | 'delete' | 'cancel';
}

/**
 * Hook configuration for session events
 */
export interface SessionHookConfig {
  onSessionStart?: (session: ClaudeSession) => Promise<void>;
  onSessionEnd?: (session: ClaudeSession, reason: string) => Promise<void>;
  onMessageSent?: (message: SDKUserMessage) => Promise<void>;
  onMessageReceived?: (message: SDKAssistantMessage) => Promise<void>;
}

/**
 * Export format options
 */
export type ExportFormat = 'markdown' | 'json' | 'html' | 'pdf';

/**
 * Export configuration
 */
export interface ExportConfig {
  format: ExportFormat;
  includeMetadata: boolean;
  includeTimestamps: boolean;
  maxMessages?: number;
  outputPath?: string;
}

/**
 * Type guard functions
 */
export function isSDKUserMessage(msg: SDKMessage): msg is SDKUserMessage {
  return 'type' in msg && msg.type === 'user';
}

export function isSDKAssistantMessage(msg: SDKMessage): msg is SDKAssistantMessage {
  return 'type' in msg && msg.type === 'assistant';
}

export function isSDKSystemMessage(msg: SDKMessage): msg is SDKSystemMessage {
  return 'type' in msg && msg.type === 'system';
}

export function isSDKResultMessage(msg: SDKMessage): msg is SDKResultMessage {
  return 'type' in msg && msg.type === 'result';
}