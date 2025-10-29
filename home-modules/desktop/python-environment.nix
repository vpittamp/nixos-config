{ pkgs, lib, ... }:

# Shared Python environment for i3-project-daemon and sway-config-manager
# This prevents buildEnv conflicts from multiple Python environments
# All packages from both modules are included here

let
  # Single Python environment with ALL packages
  sharedPythonEnv = pkgs.python3.withPackages (ps: with ps; [
    # Core dependencies (shared by both)
    i3ipc          # i3/Sway IPC library
    pydantic       # Data validation
    watchdog       # File system monitoring

    # i3-project-daemon specific
    systemd        # systemd-python for sd_notify/watchdog/journald
    pytest         # Testing framework
    pytest-asyncio # Async test support
    pytest-cov     # Coverage reporting
    rich           # Terminal UI for diagnostic commands

    # sway-config-manager specific
    jsonschema     # JSON schema validation
  ]);
in
{
  config = {
    # Export the Python environment for other modules to use
    _module.args.sharedPythonEnv = sharedPythonEnv;

    # Add to home.packages so Python and all packages are available
    home.packages = [ sharedPythonEnv ];
  };
}
