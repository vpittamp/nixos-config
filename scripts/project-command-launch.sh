#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="${1:-}"
shift || true

if [[ -z "$PROJECT_DIR" || $# -eq 0 ]]; then
    echo "project-command-launch: Usage: project-command-launch.sh <project_dir> <command> [args...]" >&2
    exit 1
fi

if [[ ! -d "$PROJECT_DIR" ]]; then
    echo "project-command-launch: directory does not exist: $PROJECT_DIR" >&2
    exit 1
fi

cd "$PROJECT_DIR"
exec "$@"
