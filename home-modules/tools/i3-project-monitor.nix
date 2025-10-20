# i3 Project Monitor Home Manager Module
# Terminal-based monitoring tool for i3 project management system

{ config, lib, pkgs, ... }:

let
  # Create Python package for i3-project-monitor
  i3-project-monitor = pkgs.python3Packages.buildPythonApplication {
    pname = "i3-project-monitor";
    version = "0.1.0";
    format = "pyproject";

    # Use relative path from module location
    src = ./i3_project_monitor;

    # Create pyproject.toml for build
    nativeBuildInputs = with pkgs.python3Packages; [
      setuptools
      wheel
    ];

    propagatedBuildInputs = with pkgs.python3Packages; [
      i3ipc  # i3ipc.aio for tree mode
      rich   # Terminal UI library
    ];

    # No tests for now (manual testing via quickstart.md)
    doCheck = false;

    # Create proper source layout and pyproject.toml before build
    preBuild = ''
      # Create proper package structure (setuptools expects package dir inside source root)
      mkdir -p i3_project_monitor
      cp -r * i3_project_monitor/ 2>/dev/null || true

      cat > pyproject.toml <<'EOF'
[build-system]
requires = ["setuptools>=61.0", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "i3-project-monitor"
version = "0.1.0"
description = "Terminal-based monitoring tool for i3 project management"
requires-python = ">=3.11"
dependencies = [
    "i3ipc",
    "rich",
]

[project.scripts]
i3-project-monitor = "i3_project_monitor.__main__:main"

[tool.setuptools.packages.find]
where = ["."]
include = ["i3_project_monitor*"]
EOF
    '';

    meta = with lib; {
      description = "Terminal-based monitoring tool for i3 project management system";
      maintainers = [ ];
      platforms = platforms.linux;
    };
  };

in
{
  # Add i3-project-monitor to user packages
  home.packages = [ i3-project-monitor ];
}
