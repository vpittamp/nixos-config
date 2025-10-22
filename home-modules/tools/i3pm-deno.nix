{ config, lib, pkgs, ... }:

let
  # Deno dependencies - fixed-output derivation for dependency caching
  denoDeps = pkgs.stdenv.mkDerivation {
    pname = "i3pm-deno-deps";
    version = "2.0.0";

    src = ./i3pm-deno;

    nativeBuildInputs = [ pkgs.deno ];

    buildPhase = ''
      export DENO_DIR=$out
      deno cache main.ts
    '';

    installPhase = ''
      # Dependencies are already in $out from DENO_DIR
      echo "Deno dependencies cached"
    '';

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-q0Zj+jQ1M9dZd9X8Fb9SzBpwZsDXZbgw0FDsdxR+sFA=";
  };

  # i3pm Deno CLI - Compiled TypeScript CLI for i3 project management
  i3pm = pkgs.stdenv.mkDerivation {
    pname = "i3pm";
    version = "2.0.0";

    src = ./i3pm-deno;

    nativeBuildInputs = [ pkgs.deno ];

    buildPhase = ''
      # Use pre-cached dependencies from denoDeps
      export DENO_DIR=${denoDeps}

      # Compile TypeScript to standalone executable
      # The cache is already populated from denoDeps
      # Use --no-remote and --cached-only to prevent network access during compilation
      # Permissions are baked into the binary at compile time
      deno compile \
        --no-remote \
        --cached-only \
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
