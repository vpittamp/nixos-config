{ pkgs, lib, ... }:

# Feature 035: i3pm CLI - Nix packaging for Deno-based project manager
#
# This derivation compiles the i3pm TypeScript CLI to a self-contained binary
# using Deno's compile feature. The result is a single executable with all
# dependencies bundled.

pkgs.stdenv.mkDerivation rec {
  pname = "i3pm";
  version = "2.0.0";

  src = ./.;

  nativeBuildInputs = with pkgs; [
    deno
  ];

  # Deno compile needs network access during build to fetch dependencies
  # We handle this by allowing network access in the build sandbox
  __noChroot = true;

  buildPhase = ''
    # Create output directory
    mkdir -p dist

    # Compile TypeScript to standalone binary
    # --allow-all: i3pm needs full system access for:
    #   - Reading /proc/<pid>/environ (environment variables)
    #   - IPC socket communication with daemon
    #   - File I/O for projects, layouts, registry
    #   - Running xprop, i3-msg commands
    deno compile \
      --allow-all \
      --output dist/i3pm \
      src/main.ts

    echo "Built i3pm binary: dist/i3pm"
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp dist/i3pm $out/bin/

    # Set executable permissions
    chmod +x $out/bin/i3pm

    echo "Installed i3pm to $out/bin/i3pm"
  '';

  meta = with lib; {
    description = "i3 Project Manager - Registry-centric workspace and window management";
    longDescription = ''
      i3pm is a command-line tool for managing project-scoped workspaces in i3
      window manager. It provides:

      - Registry-based application launching with environment injection
      - Project-scoped window filtering via /proc environment reading
      - Deterministic window matching using unique instance IDs
      - Layout capture and restore with exact window identification
      - CLI for monitoring daemon status and debugging

      Feature 035: Complete rewrite using environment-based filtering,
      replacing the old tag-based system.
    '';
    homepage = "https://github.com/yourusername/nixos-config";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.linux;
  };
}
