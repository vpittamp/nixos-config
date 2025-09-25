#!/usr/bin/env bash
# Clean home-manager backup conflicts

set -e

echo "Cleaning home-manager backup files..."

# Find and remove all .backup files created by home-manager
find "$HOME" -name "*.backup" -type f 2>/dev/null | while read -r file; do
    echo "Removing: $file"
    rm -f "$file"
done

# Also clean any .hm-backup files from old configuration
find "$HOME" -name "*.hm-backup" -type f 2>/dev/null | while read -r file; do
    echo "Removing old backup: $file"
    rm -f "$file"
done

echo "Backup conflicts cleaned."
