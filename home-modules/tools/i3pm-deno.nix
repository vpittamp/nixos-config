{ config, lib, pkgs, ... }:

let
  # i3pm Deno CLI - Compiled TypeScript CLI for i3 project management
  i3pm = pkgs.stdenv.mkDerivation {
    pname = "i3pm";
    version = "2.0.0";

    src = ./i3pm-deno;

    nativeBuildInputs = [ pkgs.deno ];

    buildPhase = ''
      # Compile TypeScript to standalone executable
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

    # Create shell aliases for convenience (optional)
    programs.bash.shellAliases = lib.mkIf config.programs.bash.enable {
      pswitch = "i3pm project switch";
      pclear = "i3pm project clear";
      plist = "i3pm project list";
      pcurrent = "i3pm project current";
      iwin = "i3pm windows";
      iwinlive = "i3pm windows --live";
      iwintable = "i3pm windows --table";
      dstatus = "i3pm daemon status";
      devents = "i3pm daemon events";
    };

    # Fish shell aliases (if using fish)
    programs.fish.shellAliases = lib.mkIf config.programs.fish.enable {
      pswitch = "i3pm project switch";
      pclear = "i3pm project clear";
      plist = "i3pm project list";
      pcurrent = "i3pm project current";
      iwin = "i3pm windows";
      iwinlive = "i3pm windows --live";
      iwintable = "i3pm windows --table";
      dstatus = "i3pm daemon status";
      devents = "i3pm daemon events";
    };
  };
}
