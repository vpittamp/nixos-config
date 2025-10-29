#!/usr/bin/env python3
"""
Configuration migration tool for Sway Configuration Manager.

Feature 047 Phase 8 T065: Convert existing Nix-only config to dynamic config format

This tool helps users migrate from static NixOS configuration to the new
dynamic configuration management system.

Usage:
    ./migrate_config.py --sway-config /path/to/sway/config --output-dir ~/.config/sway
"""

import argparse
import json
import logging
import re
import sys
from pathlib import Path
from typing import Dict, List, Tuple

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)


class SwayConfigMigrator:
    """Migrates Sway configuration from Nix/static format to dynamic format."""

    def __init__(self, sway_config_path: Path, output_dir: Path):
        """
        Initialize migrator.

        Args:
            sway_config_path: Path to existing Sway config file
            output_dir: Output directory for generated configuration files
        """
        self.sway_config_path = sway_config_path
        self.output_dir = output_dir
        self.keybindings: List[Dict] = []
        self.window_rules: List[Dict] = []
        self.workspace_assignments: List[Dict] = []

    def migrate(self) -> bool:
        """
        Run full migration process.

        Returns:
            True if migration successful, False otherwise
        """
        logger.info(f"Starting migration from {self.sway_config_path}")

        if not self.sway_config_path.exists():
            logger.error(f"Config file not found: {self.sway_config_path}")
            return False

        # Read source config
        try:
            config_content = self.sway_config_path.read_text()
        except Exception as e:
            logger.error(f"Failed to read config file: {e}")
            return False

        # Extract configuration elements
        self._extract_keybindings(config_content)
        self._extract_window_rules(config_content)
        self._extract_workspace_assignments(config_content)

        # Write output files
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self._write_keybindings_toml()
        self._write_window_rules_json()
        self._write_workspace_assignments_json()

        logger.info("Migration complete!")
        logger.info(f"Extracted {len(self.keybindings)} keybindings")
        logger.info(f"Extracted {len(self.window_rules)} window rules")
        logger.info(f"Extracted {len(self.workspace_assignments)} workspace assignments")
        logger.info(f"Output files written to: {self.output_dir}")

        return True

    def _extract_keybindings(self, config_content: str):
        """Extract keybindings from Sway config."""
        logger.info("Extracting keybindings...")

        # Match lines like: bindsym Mod+Return exec terminal
        # Also match bindcode for hardware key codes
        keybinding_pattern = re.compile(r"^\s*bindsym\s+([^\s]+)\s+(.+?)(?:\s*#\s*(.+))?$", re.MULTILINE)

        for match in keybinding_pattern.finditer(config_content):
            key_combo = match.group(1)
            command = match.group(2).strip()
            description = match.group(3).strip() if match.group(3) else ""

            # Skip if it's a mode binding or special command
            if "mode" in command.lower() and "--no-startup-id" not in command:
                continue

            # Clean up command (remove --no-startup-id, quotes, etc.)
            command = command.replace("--no-startup-id", "").strip()
            command = command.strip('"\'')

            self.keybindings.append({
                "key_combo": key_combo,
                "action": command,
                "description": description or f"Execute {command.split()[1] if len(command.split()) > 1 else 'command'}"
            })

        logger.info(f"Extracted {len(self.keybindings)} keybindings")

    def _extract_window_rules(self, config_content: str):
        """Extract window rules from Sway config."""
        logger.info("Extracting window rules...")

        # Match for_window patterns
        # Example: for_window [app_id="calculator"] floating enable
        for_window_pattern = re.compile(
            r"^\s*for_window\s+\[([^\]]+)\]\s+(.+?)(?:\s*#\s*(.+))?$",
            re.MULTILINE
        )

        rule_id_counter = 1
        for match in for_window_pattern.finditer(config_content):
            criteria_str = match.group(1)
            actions_str = match.group(2).strip()
            description = match.group(3).strip() if match.group(3) else ""

            # Parse criteria
            criteria = self._parse_criteria(criteria_str)
            if not criteria:
                continue

            # Parse actions
            actions_list = [a.strip() for a in actions_str.split(";") if a.strip()]

            # Convert actions to dict format
            actions = self._convert_actions(actions_list)

            self.window_rules.append({
                "rule_id": f"migrated_rule_{rule_id_counter}",
                "criteria": criteria,
                "actions": actions,
                "priority": 100,
                "description": description
            })

            rule_id_counter += 1

        logger.info(f"Extracted {len(self.window_rules)} window rules")

    def _extract_workspace_assignments(self, config_content: str):
        """Extract workspace assignments from Sway config."""
        logger.info("Extracting workspace assignments...")

        # Match workspace to output assignments
        # Example: workspace 1 output DP-1
        workspace_pattern = re.compile(
            r"^\s*workspace\s+(\d+)\s+output\s+([^\s]+)(?:\s+([^\s]+))?",
            re.MULTILINE
        )

        for match in workspace_pattern.finditer(config_content):
            workspace_num = int(match.group(1))
            primary_output = match.group(2)
            fallback_output = match.group(3) if match.group(3) else None

            assignment = {
                "workspace_number": workspace_num,
                "primary_output": primary_output
            }

            if fallback_output:
                assignment["fallback_output"] = fallback_output

            self.workspace_assignments.append(assignment)

        logger.info(f"Extracted {len(self.workspace_assignments)} workspace assignments")

    def _parse_criteria(self, criteria_str: str) -> Dict:
        """Parse window criteria string into dict."""
        criteria = {}

        # Split by whitespace, handling quoted values
        parts = re.findall(r'(\w+)=(["\']?)([^"\']*)\2', criteria_str)

        for key, _, value in parts:
            if key == "class":
                criteria["window_class"] = value
            elif key == "app_id":
                criteria["app_id"] = value
            elif key == "title":
                criteria["title"] = value
            elif key == "instance":
                criteria["instance"] = value

        return criteria

    def _convert_actions(self, actions_list: List[str]) -> Dict:
        """Convert action strings to action dict."""
        actions = {}

        for action in actions_list:
            if "floating enable" in action:
                actions["floating"] = True
            elif "floating disable" in action:
                actions["floating"] = False
            elif action.startswith("resize set"):
                # Parse: resize set 400 300
                parts = action.split()
                if len(parts) >= 4:
                    actions["resize"] = {
                        "width": int(parts[2]),
                        "height": int(parts[3])
                    }
            elif action.startswith("move"):
                if "position center" in action:
                    actions["move"] = "center"
                elif "workspace" in action:
                    # Extract workspace number/name
                    ws_match = re.search(r"workspace\s+(\S+)", action)
                    if ws_match:
                        try:
                            actions["workspace"] = int(ws_match.group(1))
                        except ValueError:
                            actions["workspace"] = ws_match.group(1)

        return actions

    def _write_keybindings_toml(self):
        """Write keybindings to TOML file."""
        output_file = self.output_dir / "keybindings-migrated.toml"

        with open(output_file, "w") as f:
            f.write("# Migrated keybindings from Sway config\n")
            f.write("# Generated by migrate_config.py\n\n")
            f.write("[keybindings]\n\n")

            for kb in self.keybindings:
                if kb["description"]:
                    f.write(f"# {kb['description']}\n")
                f.write(f'"{kb["key_combo"]}" = ')
                f.write('{ ')
                f.write(f'command = "{kb["action"]}", ')
                f.write(f'description = "{kb["description"]}"')
                f.write(' }\n\n')

        logger.info(f"Wrote keybindings to {output_file}")

    def _write_window_rules_json(self):
        """Write window rules to JSON file."""
        output_file = self.output_dir / "window-rules-migrated.json"

        data = {
            "version": "1.0",
            "rules": self.window_rules
        }

        with open(output_file, "w") as f:
            json.dump(data, f, indent=2)

        logger.info(f"Wrote window rules to {output_file}")

    def _write_workspace_assignments_json(self):
        """Write workspace assignments to JSON file."""
        output_file = self.output_dir / "workspace-assignments-migrated.json"

        data = {
            "version": "1.0",
            "assignments": self.workspace_assignments
        }

        with open(output_file, "w") as f:
            json.dump(data, f, indent=2)

        logger.info(f"Wrote workspace assignments to {output_file}")


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Migrate Sway configuration to dynamic config format",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Migrate from default Sway config
  %(prog)s --sway-config ~/.config/sway/config

  # Migrate with custom output directory
  %(prog)s --sway-config ~/.config/sway/config --output-dir ~/sway-migrated

  # Migrate from Nix-generated config
  %(prog)s --sway-config /etc/profiles/per-user/$USER/etc/sway/config

After migration:
  1. Review generated files in output directory
  2. Compare with your existing configuration
  3. Merge generated files into your dynamic config:
     cat ~/.config/sway/keybindings-migrated.toml >> ~/.config/sway/keybindings.toml
  4. Validate and reload:
     swayconfig validate && swayconfig reload
"""
    )

    parser.add_argument(
        "--sway-config",
        type=Path,
        default=Path.home() / ".config" / "sway" / "config",
        help="Path to existing Sway config file (default: ~/.config/sway/config)"
    )

    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path.home() / ".config" / "sway",
        help="Output directory for migrated config files (default: ~/.config/sway)"
    )

    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Enable verbose logging"
    )

    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    # Run migration
    migrator = SwayConfigMigrator(args.sway_config, args.output_dir)
    success = migrator.migrate()

    if success:
        print("\n✅ Migration completed successfully!")
        print(f"\nGenerated files:")
        print(f"  • {args.output_dir}/keybindings-migrated.toml")
        print(f"  • {args.output_dir}/window-rules-migrated.json")
        print(f"  • {args.output_dir}/workspace-assignments-migrated.json")
        print(f"\nNext steps:")
        print(f"  1. Review generated files")
        print(f"  2. Merge into your dynamic config")
        print(f"  3. Validate: swayconfig validate")
        print(f"  4. Reload: swayconfig reload")
        return 0
    else:
        print("\n❌ Migration failed. Check logs above for details.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
