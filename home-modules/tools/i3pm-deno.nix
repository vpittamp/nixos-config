{ config, lib, pkgs, ... }:

let
  # i3pm Deno CLI - Compiled TypeScript CLI for i3 project management
  i3pm = pkgs.stdenv.mkDerivation {
    pname = "i3pm";
    version = "2.0.0";

    src = ./i3pm-deno;

    nativeBuildInputs = [ pkgs.deno ];

    # Set DENO_DIR to a writable location and cache dependencies
    DENO_DIR = ".deno-cache";

    configurePhase = ''
      export DENO_DIR=$PWD/.deno-cache
      mkdir -p $DENO_DIR

      # Cache dependencies before compilation
      # This downloads all dependencies into the cache
      deno cache \
        --reload \
        main.ts
    '';

    buildPhase = ''
      # Compile TypeScript to standalone executable
      # The cache is already populated from configurePhase
      # Permissions are baked into the binary at compile time
      deno compile \
        --allow-net \
        --allow-read=/run/user,/home \
        --allow-env=XDG_RUNTIME_DIR,HOME,USER \
        --output=i3pm \
        main.ts
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp i3pm $out/bin/
    '';

    # Allow network access during build for downloading dependencies
    __noChroot = true;

    meta = with lib; {
      description = "i3 project management CLI tool";
      longDescription = ''
        Type-safe, compiled CLI for i3 project context switching and window management.
        Communicates with i3-project-event-daemon via JSON-RPC 2.0 over Unix socket.

        Features:
        - Project context switching with window visibility management
        - Real-time window state visualization (tree, table, JSON, live TUI)
        - Daemon status and event monitoring
        - Window classification rules management
        - Interactive multi-pane monitoring dashboard

        Replaces the Python CLI with a compiled Deno executable.
      '';
      homepage = "https://github.com/user/nixos-config";
      license = licenses.mit;
      platforms = platforms.linux;
      maintainers = [ ];
    };
  };
in
{
  config = {
    # Install i3pm binary
    home.packages = [ i3pm ];

    # Note: Shell aliases are managed in home-modules/shell/bash.nix
    # to avoid conflicts. The bash.nix file should be updated to use
    # the new i3pm commands instead of the old shell scripts.
  };
}
