-- Migration: 029_add_systemd_proc_fields.sql
-- Feature: 029-linux-system-log
-- Purpose: Add systemd and process monitoring fields to event_log table
-- Author: Feature 029 Implementation
-- Date: 2025-10-23

-- ============================================================================
-- Phase 1: Extend source check constraint
-- ============================================================================

-- Note: SQLite doesn't support ALTER TABLE DROP CONSTRAINT and ADD CONSTRAINT
-- in a clean way. We'll need to recreate the check constraint if it exists.
-- For now, we'll add the columns and rely on EventEntry validation in Python.

-- ============================================================================
-- Phase 2: Add systemd event fields
-- ============================================================================

-- Service unit name (e.g., "app-firefox-123.service")
ALTER TABLE event_log ADD COLUMN systemd_unit TEXT;

-- systemd message (e.g., "Started Firefox Web Browser")
ALTER TABLE event_log ADD COLUMN systemd_message TEXT;

-- Process ID from journal _PID field
ALTER TABLE event_log ADD COLUMN systemd_pid INTEGER;

-- Journal cursor for event position (for pagination)
ALTER TABLE event_log ADD COLUMN journal_cursor TEXT;

-- ============================================================================
-- Phase 3: Add process event fields
-- ============================================================================

-- Process ID
ALTER TABLE event_log ADD COLUMN process_pid INTEGER;

-- Command name from /proc/{pid}/comm
ALTER TABLE event_log ADD COLUMN process_name TEXT;

-- Full command line (sanitized, truncated to 500 chars)
ALTER TABLE event_log ADD COLUMN process_cmdline TEXT;

-- Parent process ID from /proc/{pid}/stat
ALTER TABLE event_log ADD COLUMN process_parent_pid INTEGER;

-- Process start time from /proc/{pid}/stat (for correlation)
ALTER TABLE event_log ADD COLUMN process_start_time INTEGER;

-- ============================================================================
-- Phase 4: Create indexes for performance
-- ============================================================================

-- Index on source for efficient filtering by event source
CREATE INDEX IF NOT EXISTS idx_event_log_source ON event_log(source);

-- Index on systemd_unit for filtering systemd service events
CREATE INDEX IF NOT EXISTS idx_event_log_systemd_unit ON event_log(systemd_unit);

-- Index on process_pid for process event queries
CREATE INDEX IF NOT EXISTS idx_event_log_process_pid ON event_log(process_pid);

-- Index on process_parent_pid for correlation queries
CREATE INDEX IF NOT EXISTS idx_event_log_process_parent_pid ON event_log(process_parent_pid);

-- ============================================================================
-- Phase 5: Create event_correlations tables
-- ============================================================================

-- Main correlations table
CREATE TABLE IF NOT EXISTS event_correlations (
    correlation_id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT NOT NULL,
    confidence_score REAL NOT NULL CHECK(confidence_score >= 0.0 AND confidence_score <= 1.0),

    parent_event_id INTEGER NOT NULL,
    correlation_type TEXT NOT NULL CHECK(correlation_type IN ('window_to_process', 'process_to_subprocess')),

    time_delta_ms REAL NOT NULL,
    detection_window_ms REAL DEFAULT 5000.0,

    timing_factor REAL,
    hierarchy_factor REAL,
    name_similarity REAL,
    workspace_match INTEGER DEFAULT 0,  -- SQLite boolean

    FOREIGN KEY (parent_event_id) REFERENCES event_log(event_id) ON DELETE CASCADE
);

-- Child events junction table
CREATE TABLE IF NOT EXISTS correlation_children (
    correlation_id INTEGER NOT NULL,
    child_event_id INTEGER NOT NULL,
    sequence_order INTEGER NOT NULL,  -- Order in which child was spawned

    PRIMARY KEY (correlation_id, child_event_id),
    FOREIGN KEY (correlation_id) REFERENCES event_correlations(correlation_id) ON DELETE CASCADE,
    FOREIGN KEY (child_event_id) REFERENCES event_log(event_id) ON DELETE CASCADE
);

-- Indexes for correlation queries
CREATE INDEX IF NOT EXISTS idx_correlations_parent ON event_correlations(parent_event_id);
CREATE INDEX IF NOT EXISTS idx_correlations_confidence ON event_correlations(confidence_score);
CREATE INDEX IF NOT EXISTS idx_correlation_children_child ON correlation_children(child_event_id);

-- ============================================================================
-- Migration complete
-- ============================================================================

-- Verify migration
SELECT 'Migration 029 completed successfully' AS status;
