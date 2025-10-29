#!/usr/bin/env python3
"""
Sway Configuration Manager CLI

Command-line interface for managing Sway configuration.
"""

import argparse
import asyncio
import json
import sys
from pathlib import Path
from typing import Any, Dict, Optional


class SwayConfigCLI:
    """CLI client for Sway Configuration Manager."""

    def __init__(self):
        """Initialize CLI client."""
        self.socket_path = Path.home() / ".cache" / "sway-config-manager" / "ipc.sock"

    async def send_request(self, method: str, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """
        Send JSON-RPC request to daemon.

        Args:
            method: RPC method name
            params: Method parameters

        Returns:
            Response dict

        Raises:
            ConnectionError: If cannot connect to daemon
            RuntimeError: If request fails
        """
        if not self.socket_path.exists():
            raise ConnectionError(f"Daemon not running (socket not found: {self.socket_path})")

        request = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params or {},
            "id": 1
        }

        try:
            reader, writer = await asyncio.open_unix_connection(str(self.socket_path))

            # Send request
            writer.write((json.dumps(request) + "\n").encode())
            await writer.drain()

            # Read response
            data = await reader.readline()
            response = json.loads(data.decode())

            writer.close()
            await writer.wait_closed()

            if "error" in response:
                raise RuntimeError(f"RPC error: {response['error']['message']}")

            return response.get("result", {})

        except Exception as e:
            raise RuntimeError(f"Failed to communicate with daemon: {e}")

    async def cmd_reload(self, args):
        """Reload configuration."""
        params = {
            "validate_only": args.validate_only,
            "skip_commit": args.skip_commit
        }

        if args.files:
            params["files"] = args.files.split(",")

        result = await self.send_request("config_reload", params)

        if result.get("success"):
            print("✅ Configuration reloaded successfully")
            if result.get("warnings"):
                print(f"⚠️  {len(result['warnings'])} warnings")
        else:
            print("❌ Configuration reload failed")
            for error in result.get("errors", []):
                print(f"  Error: {error.get('message', error)}")

        return 0 if result.get("success") else 1

    async def cmd_validate(self, args):
        """Validate configuration."""
        params = {}
        if args.files:
            params["files"] = args.files.split(",")
        if args.strict:
            params["strict"] = True

        result = await self.send_request("config_validate", params)

        if result.get("valid"):
            print("✅ Configuration valid")
        else:
            print("❌ Validation failed")

        for error in result.get("errors", []):
            print(f"\n{error.get('file_path', 'unknown')}:")
            print(f"  {error.get('error_type', 'error').upper()}: {error.get('message')}")
            if error.get("suggestion"):
                print(f"  → {error['suggestion']}")

        return 0 if result.get("valid") else 1

    async def cmd_rollback(self, args):
        """Rollback to previous version."""
        params = {
            "commit_hash": args.commit,
            "no_reload": args.no_reload
        }

        result = await self.send_request("config_rollback", params)

        if result.get("success"):
            print(f"✅ Rolled back to {args.commit[:8]}")
        else:
            print(f"❌ Rollback failed: {result.get('error')}")

        return 0 if result.get("success") else 1

    async def cmd_versions(self, args):
        """List configuration versions."""
        params = {"limit": args.limit}

        result = await self.send_request("config_get_versions", params)

        versions = result.get("versions", [])

        if not versions:
            print("No configuration versions found")
            return 0

        print("\n═══════════════════════════════════════════════════════")
        print("  CONFIGURATION VERSIONS")
        print("═══════════════════════════════════════════════════════")

        for version in versions:
            is_active = version.get("is_active", False)
            marker = "●" if is_active else " "
            commit = version["commit_hash"][:8]
            timestamp = version.get("timestamp", "")
            message = version.get("message", "")

            print(f"{marker} {commit}  {timestamp}")
            print(f"  {message}")
            print()

        return 0

    async def cmd_show(self, args):
        """Show current configuration."""
        params = {
            "category": args.category,
            "sources": args.sources
        }

        if args.project:
            params["project"] = args.project

        result = await self.send_request("config_show", params)

        if args.json:
            print(json.dumps(result, indent=2))
            return 0

        # Pretty print configuration
        if "keybindings" in result:
            print("\n═══════════════════════════════════════════════════════")
            print("  KEYBINDINGS")
            print("═══════════════════════════════════════════════════════")
            for kb in result["keybindings"]:
                print(f"{kb['key_combo']:20} → {kb['command']}")
                if kb.get("description"):
                    print(f"{'':20}   {kb['description']}")

        if "window_rules" in result:
            print("\n═══════════════════════════════════════════════════════")
            print("  WINDOW RULES")
            print("═══════════════════════════════════════════════════════")
            for rule in result["window_rules"]:
                print(f"Rule {rule['id']}: {rule['scope']}")
                criteria = rule.get("criteria", {})
                for key, value in criteria.items():
                    if value:
                        print(f"  {key}: {value}")
                print(f"  actions: {', '.join(rule['actions'])}")
                print()

        return 0

    async def cmd_conflicts(self, args):
        """Show configuration conflicts."""
        result = await self.send_request("config_get_conflicts", {})

        conflicts = result.get("conflicts", [])

        if not conflicts:
            print("✅ No configuration conflicts")
            return 0

        print("\n⚠️  CONFIGURATION CONFLICTS\n")

        for conflict in conflicts:
            print(f"Type: {conflict['type']}")
            if conflict['type'] == 'keybinding':
                print(f"Key: {conflict['key']}")
            elif conflict['type'] == 'workspace_assignment':
                print(f"Workspace: {conflict['workspace']}")

            print(f"Sources: {' vs '.join(conflict['sources'])}")
            print(f"Resolution: Using {conflict['resolution']}")
            print()

        return 0

    async def cmd_ping(self, args):
        """Ping daemon to check if running."""
        try:
            result = await self.send_request("ping", {})
            if result.get("status") == "ok":
                print("✅ Daemon is running")
                return 0
            else:
                print("⚠️  Daemon responded but status is not OK")
                return 1
        except ConnectionError as e:
            print(f"❌ Daemon not running: {e}")
            return 1
        except Exception as e:
            print(f"❌ Error: {e}")
            return 1

    def run(self):
        """Run CLI."""
        parser = argparse.ArgumentParser(
            description="Sway Configuration Manager CLI",
            prog="swayconfig"
        )

        subparsers = parser.add_subparsers(dest="command", help="Command to execute")

        # Reload command
        reload_parser = subparsers.add_parser("reload", help="Reload configuration")
        reload_parser.add_argument("--files", help="Specific files to reload (comma-separated)")
        reload_parser.add_argument("--validate-only", action="store_true", help="Only validate, don't apply")
        reload_parser.add_argument("--skip-commit", action="store_true", help="Don't commit changes to git")

        # Validate command
        validate_parser = subparsers.add_parser("validate", help="Validate configuration")
        validate_parser.add_argument("--files", help="Specific files to validate (comma-separated)")
        validate_parser.add_argument("--strict", action="store_true", help="Treat warnings as errors")

        # Rollback command
        rollback_parser = subparsers.add_parser("rollback", help="Rollback to previous version")
        rollback_parser.add_argument("commit", help="Commit hash to rollback to")
        rollback_parser.add_argument("--no-reload", action="store_true", help="Don't reload after rollback")

        # Versions command
        versions_parser = subparsers.add_parser("versions", help="List configuration versions")
        versions_parser.add_argument("--limit", type=int, default=10, help="Maximum versions to show")

        # Show command
        show_parser = subparsers.add_parser("show", help="Show current configuration")
        show_parser.add_argument("--category", choices=["all", "keybindings", "window-rules", "workspaces"], default="all")
        show_parser.add_argument("--sources", action="store_true", help="Show source attribution")
        show_parser.add_argument("--project", help="Show project-specific configuration")
        show_parser.add_argument("--json", action="store_true", help="Output as JSON")

        # Conflicts command
        conflicts_parser = subparsers.add_parser("conflicts", help="Show configuration conflicts")

        # Ping command
        ping_parser = subparsers.add_parser("ping", help="Check if daemon is running")

        args = parser.parse_args()

        if not args.command:
            parser.print_help()
            return 1

        # Route to command handler
        cmd_map = {
            "reload": self.cmd_reload,
            "validate": self.cmd_validate,
            "rollback": self.cmd_rollback,
            "versions": self.cmd_versions,
            "show": self.cmd_show,
            "conflicts": self.cmd_conflicts,
            "ping": self.cmd_ping,
        }

        handler = cmd_map.get(args.command)
        if not handler:
            print(f"Unknown command: {args.command}")
            return 1

        try:
            return asyncio.run(handler(args))
        except KeyboardInterrupt:
            print("\nInterrupted")
            return 130
        except Exception as e:
            print(f"❌ Error: {e}")
            return 1


def main():
    """Main entry point."""
    cli = SwayConfigCLI()
    sys.exit(cli.run())


if __name__ == "__main__":
    main()
