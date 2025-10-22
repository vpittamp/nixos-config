{ config, lib, pkgs, ... }:

let
  # i3pm Deno CLI - Wrapper script that runs TypeScript with Deno runtime
  i3pm = pkgs.stdenv.mkDerivation {
    pname = "i3pm";
    version = "2.0.0";

    src = ./i3pm-deno;

    dontBuild = true;

    installPhase = ''
      mkdir -p $out/share/i3pm
      cp -r * $out/share/i3pm/

      mkdir -p $out/bin
      cat > $out/bin/i3pm <<EOF
#!/usr/bin/env bash
exec ${pkgs.deno}/bin/deno run \\
  --no-lock \\
  --allow-net \\
  --allow-read=/run/user,/home \\
  --allow-env=XDG_RUNTIME_DIR,HOME,USER \\
  $out/share/i3pm/main.ts "\$@"
EOF
      chmod +x $out/bin/i3pm
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
