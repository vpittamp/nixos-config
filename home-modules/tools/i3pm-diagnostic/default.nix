{ pkgs, lib, ... }:

# Feature 039: i3pm-diagnostic CLI - Diagnostic tooling for i3 project management
#
# This derivation packages the Python-based diagnostic CLI that provides
# introspection and troubleshooting commands for the i3 project daemon.

pkgs.python3Packages.buildPythonApplication rec {
  pname = "i3pm-diagnostic";
  version = "1.0.0";

  # Source is this directory
  src = ./.;

  # Python dependencies
  propagatedBuildInputs = with pkgs.python3Packages; [
    click          # CLI framework
    rich           # Terminal UI formatting
    pydantic       # Data validation (for models.py)
  ];

  # Format: setuptools (using pyproject.toml or setup.py)
  format = "other";

  # Install phase - copy Python modules and create executable
  installPhase = ''
    mkdir -p $out/bin
    mkdir -p $out/lib/python${pkgs.python3.pythonVersion}/site-packages/i3pm_diagnostic

    # Copy Python modules
    cp -r __init__.py __main__.py models.py displays/ $out/lib/python${pkgs.python3.pythonVersion}/site-packages/i3pm_diagnostic/

    # Create executable wrapper script
    cat > $out/bin/i3pm-diagnose << 'EOF'
#!/usr/bin/env bash
# i3pm-diagnostic CLI entry point
exec ${pkgs.python3}/bin/python3 -m i3pm_diagnostic "$@"
EOF

    chmod +x $out/bin/i3pm-diagnose

    echo "Installed i3pm-diagnostic to $out/bin/i3pm-diagnose"
  '';

  # Skip build phase (no compilation needed for Python)
  dontBuild = true;

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
