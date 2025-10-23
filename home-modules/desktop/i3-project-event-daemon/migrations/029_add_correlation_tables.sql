-- Feature 029: Linux System Log Integration - User Story 3
-- Add EventCorrelation tables for storing detected event relationships
--
-- Migration: 029_add_correlation_tables
-- Created: 2025-10-23
-- Purpose: Support correlation detection between window events and process spawns

-- ============================================================================
-- Table: event_correlations
-- Purpose: Store detected correlations between parent and child events
-- ============================================================================

CREATE TABLE IF NOT EXISTS event_correlations (
    -- Primary key
    correlation_id INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Metadata
    created_at TEXT NOT NULL,  -- ISO 8601 timestamp when correlation was detected
    confidence_score REAL NOT NULL CHECK(confidence_score >= 0.0 AND confidence_score <= 1.0),

    -- Event relationships
    parent_event_id INTEGER NOT NULL,
    correlation_type TEXT NOT NULL CHECK(correlation_type IN ('window_to_process', 'process_to_subprocess')),

    -- Timing information
    time_delta_ms REAL NOT NULL CHECK(time_delta_ms >= 0),
    detection_window_ms REAL DEFAULT 5000.0,

    -- Correlation factors (for debugging and analysis)
    timing_factor REAL CHECK(timing_factor >= 0.0 AND timing_factor <= 1.0),
    hierarchy_factor REAL CHECK(hierarchy_factor >= 0.0 AND hierarchy_factor <= 1.0),
    name_similarity REAL CHECK(name_similarity >= 0.0 AND name_similarity <= 1.0),
    workspace_match INTEGER DEFAULT 0,  -- SQLite boolean (0=false, 1=true)

    -- Foreign key constraint
    FOREIGN KEY (parent_event_id) REFERENCES event_log(event_id) ON DELETE CASCADE
);

-- ============================================================================
-- Table: correlation_children
-- Purpose: Many-to-many relationship between correlations and child events
-- ============================================================================

CREATE TABLE IF NOT EXISTS correlation_children (
    -- Composite primary key
    correlation_id INTEGER NOT NULL,
    child_event_id INTEGER NOT NULL,

    -- Sequence order: Order in which child was spawned (1st child, 2nd child, etc.)
    sequence_order INTEGER NOT NULL CHECK(sequence_order > 0),

    PRIMARY KEY (correlation_id, child_event_id),

    -- Foreign key constraints
    FOREIGN KEY (correlation_id) REFERENCES event_correlations(correlation_id) ON DELETE CASCADE,
    FOREIGN KEY (child_event_id) REFERENCES event_log(event_id) ON DELETE CASCADE
);

-- ============================================================================
-- Indexes for query performance
-- ============================================================================

-- Index for looking up correlations by parent event
CREATE INDEX IF NOT EXISTS idx_correlations_parent
    ON event_correlations(parent_event_id);

-- Index for filtering correlations by confidence score
CREATE INDEX IF NOT EXISTS idx_correlations_confidence
    ON event_correlations(confidence_score);

-- Index for filtering by correlation type
CREATE INDEX IF NOT EXISTS idx_correlations_type
    ON event_correlations(correlation_type);

-- Index for looking up correlations by child event
CREATE INDEX IF NOT EXISTS idx_correlation_children_child
    ON correlation_children(child_event_id);

-- Index for ordering children by sequence
CREATE INDEX IF NOT EXISTS idx_correlation_children_sequence
    ON correlation_children(correlation_id, sequence_order);

-- ============================================================================
-- Migration validation
-- ============================================================================

-- Verify tables were created
SELECT
    'event_correlations' AS table_name,
    COUNT(*) AS column_count
FROM pragma_table_info('event_correlations')
UNION ALL
SELECT
    'correlation_children' AS table_name,
    COUNT(*) AS column_count
FROM pragma_table_info('correlation_children');

-- Verify indexes were created
SELECT
    name AS index_name,
    tbl_name AS table_name
FROM sqlite_master
WHERE type = 'index'
  AND (tbl_name = 'event_correlations' OR tbl_name = 'correlation_children')
  AND name LIKE 'idx_%'
ORDER BY tbl_name, name;
