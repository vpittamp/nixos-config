{ pkgs, ... }:

# Shared Python environment for i3-project-daemon and sway-config-manager
# This prevents buildEnv conflicts from multiple Python environments
# All packages from both modules are included here

{
  home.packages = with pkgs; [
    (python3.withPackages (ps: with ps; [
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
    ]))
  ];
}
