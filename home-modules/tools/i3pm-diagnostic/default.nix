{ pkgs, lib, ... }:

# Feature 039: i3pm-diagnostic CLI - Diagnostic tooling for i3 project management
#
# This derivation packages the Python-based diagnostic CLI that provides
# introspection and troubleshooting commands for the i3 project daemon.

pkgs.python3Packages.buildPythonApplication rec {
  pname = "i3pm-diagnostic";
  version = "1.0.0";

  # Source is the package subdirectory
  src = ./i3pm_diagnostic_pkg;

  # Python dependencies
  propagatedBuildInputs = with pkgs.python3Packages; [
    click          # CLI framework
    rich           # Terminal UI formatting
    pydantic       # Data validation (for models.py)
  ];

  # Format: setuptools (using setup.py)
  format = "setuptools";

  # No tests yet (pytest not available in build environment)
  doCheck = false;

  meta = with lib; {
    description = "i3pm diagnostic CLI - Troubleshooting tooling for i3 project management";
    longDescription = ''
      i3pm-diagnostic provides comprehensive diagnostic commands for troubleshooting
      window management issues in the i3 project management system.

      Commands:
      - health:    Check daemon health and event subscriptions
      - window:    Inspect window properties and identity
      - events:    View recent event history with live streaming
      - validate:  Validate daemon state consistency against i3 IPC

      Features (Feature 039):
      - JSON-RPC communication with daemon via Unix socket
      - Rich-formatted terminal output with color coding
      - Machine-readable JSON output mode (--json flag)
      - Exit codes for shell scripting integration
      - Performance targets: <50ms event detection, <100ms workspace assignment
      - State validation with drift detection
      - PWA instance identification (Firefox FFPWA-*, Chrome PWAs)
      - Window class normalization and tiered matching diagnostics

      Usage:
        i3pm-diagnose health
        i3pm-diagnose window <window_id>
        i3pm-diagnose events --limit 50 --follow
        i3pm-diagnose validate
    '';
    homepage = "https://github.com/yourusername/nixos-config";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.linux;
  };
}
