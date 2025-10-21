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
        # TUI mode - interactive Textual interface
        from i3_project_manager.tui.app import run_tui
        return run_tui()

    # CLI mode - argparse command processing
    from i3_project_manager.cli.commands import cli_main
    return cli_main()


if __name__ == "__main__":
    sys.exit(main())
