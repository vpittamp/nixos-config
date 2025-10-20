# i3 Project Test Framework Home Manager Module
# Testing and debugging framework for i3 project management system

{ config, lib, pkgs, ... }:

let
  # Create Python package for i3-project-test
  i3-project-test = pkgs.python3Packages.buildPythonApplication {
    pname = "i3-project-test";
    version = "1.0.0";
    format = "pyproject";

    # Use relative path from module location
    src = ./i3-project-test;

    # Create pyproject.toml for build
    nativeBuildInputs = with pkgs.python3Packages; [
      setuptools
      wheel
    ];

    propagatedBuildInputs = with pkgs.python3Packages; [
      i3ipc  # i3 IPC library
      rich   # Terminal UI library
    ];

    # No tests for now (manual testing via quickstart.md)
    doCheck = false;

    # Create proper source layout and pyproject.toml before build
    preBuild = ''
      # Restructure to proper Python package layout
      # Current: all files at root
      # Needed: all files under i3_project_test/ subdirectory
      mkdir -p src/i3_project_test

      # Move all Python files and directories into package
      for item in *; do
        if [ "$item" != "src" ]; then
          mv "$item" src/i3_project_test/ 2>/dev/null || true
        fi
      done

      # Move back to root for build
      mv src/i3_project_test ./
      rmdir src 2>/dev/null || true

      cat > pyproject.toml <<'EOF'
[build-system]
requires = ["setuptools>=61.0", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "i3-project-test"
version = "1.0.0"
description = "Testing and debugging framework for i3 project management"
requires-python = ">=3.11"
dependencies = [
    "i3ipc",
    "rich",
]

[project.scripts]
i3-project-test = "i3_project_test.__main__:main"

[tool.setuptools.packages.find]
where = ["."]
include = ["i3_project_test*"]
EOF
    '';

    meta = with lib; {
      description = "Testing and debugging framework for i3 project management system";
      license = licenses.mit;
      platforms = platforms.linux;
    };
  };

in {
  # Install test framework
  home.packages = [
    i3-project-test
    pkgs.tmux  # Required for test isolation
  ];

  # Create default configuration
  home.file.".config/i3-project-test/config.json".text = builtins.toJSON {
    test_timeout_seconds = 30;
    cleanup_on_failure = true;
    capture_diagnostics_on_failure = false;
    diagnostics_dir = "~/.local/share/i3-project-test/diagnostics";
    log_level = "INFO";
    tmux_session_prefix = "i3-project-test-";
    test_project_prefix = "test-";
  };

  # Create directories
  home.file.".local/share/i3-project-test/diagnostics/.keep".text = "";
  home.file.".local/share/i3-project-test/logs/.keep".text = "";
}
