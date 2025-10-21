"""Entry point for i3pm CLI/TUI application.

Mode detection:
- No arguments → Launch TUI (interactive Textual interface)
- Arguments present → Execute CLI command and exit
"""

import sys


def main() -> int:
    """Main entry point with mode detection."""
    # Mode detection: TUI if no args, CLI if args present
    if len(sys.argv) == 1:
        # TUI mode - will be implemented in Phase 6
        print("TUI mode not yet implemented. Use CLI commands for now.")
        print("Run 'i3pm --help' for available commands.")
        return 1

    # CLI mode - will be implemented in Phase 3-5
    from i3_project_manager.cli.commands import cli_main
    return cli_main()


if __name__ == "__main__":
    sys.exit(main())
