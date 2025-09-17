{ config, lib, pkgs, ... }:

let
  cfg = config.programs.headlamp;

  aiPlugin = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "headlamp-ai-assistant-plugin";
    version = "0.1.0-alpha";
    src = pkgs.fetchurl {
      url = "https://github.com/headlamp-k8s/plugins/releases/download/ai-assistant-0.1.0-alpha/headlamp-k8s-ai-assistant-0.1.0-alpha.tar.gz";
      sha256 = "sha256-RH6jTZMrDPkv4AqxPzWxRSuNQjU5VyOEiHCI8xXYzJk=";
    };
    dontBuild = true;
    unpackPhase = ''
      runHook preUnpack
      mkdir -p source
      tar -xzf "$src" -C source
      runHook postUnpack
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/plugins"
      cp -a source/ai-assistant "$out/plugins/ai-assistant"
      runHook postInstall
    '';
    meta = with pkgs.lib; {
      description = "Headlamp AI Assistant plugin";
      homepage = "https://github.com/headlamp-k8s/plugins";
      license = licenses.asl20;
      platforms = platforms.linux;
    };
  };

  esoPlugin = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "external-secrets-operator-headlamp-plugin";
    version = "0.1.0-beta7";
    src = pkgs.fetchurl {
      url = "https://github.com/magohl/external-secrets-operator-headlamp-plugin/releases/download/0.1.0-beta7/external-secrets-operator-headlamp-plugin-0.1.0-beta7.tar.gz";
      sha256 = "sha256-776NO3HJBLi8Nh0DcGyFuECozsGodwr8Obt3yX2RSh0=";
    };
    dontBuild = true;
    unpackPhase = ''
      runHook preUnpack
      mkdir -p source
      tar -xzf "$src" -C source
      runHook postUnpack
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/plugins"
      cp -a source/external-secrets-operator-headlamp-plugin "$out/plugins/external-secrets-operator-headlamp-plugin"
      runHook postInstall
    '';
    meta = with pkgs.lib; {
      description = "Headlamp plugin for External Secrets Operator";
      homepage = "https://github.com/magohl/external-secrets-operator-headlamp-plugin";
      license = licenses.asl20;
      platforms = platforms.linux;
    };
  };

  pluginsOut = pkgs.symlinkJoin {
    name = "headlamp-plugins-bundle";
    paths = [ aiPlugin esoPlugin ];
  };

  mkSecretEnvLine = name: ref:
    if ref == null || ref == "" then "" else ''--env ${name}=${ref}'';

in
{
  options.programs.headlamp = {
    enable = lib.mkEnableOption "Headlamp user configuration (plugins, wrappers)";

    installPlugins = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install predefined Headlamp plugins into the user config directory.";
    };

    aiAssistant = {
      openaiSecretRef = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
        example = "op://Personal/OpenAI API Key/credential";
        description = "1Password secret reference for OPENAI_API_KEY (op run syntax).";
      };
      anthropicSecretRef = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
        example = "op://Personal/Anthropic API Key/credential";
        description = "1Password secret reference for ANTHROPIC_API_KEY (op run syntax).";
      };
      azureOpenAISecretRef = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
        example = "op://Corp/Azure OpenAI Key/credential";
        description = "Optional 1Password secret ref for AZURE_OPENAI_API_KEY (if used).";
      };
      extraEnv = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {};
        description = "Additional environment variables to pass to Headlamp via op run (values may be op:// refs).";
      };
      createDesktopEntry = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Create a user desktop entry 'Headlamp (AI)' that injects API keys via 1Password.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Preinstall plugins for this user
    home.file.".config/Headlamp/plugins" = lib.mkIf cfg.installPlugins {
      source = pluginsOut + "/plugins";
      recursive = true;
    };

    # Wrapper that runs Headlamp via 1Password CLI with provided secret refs
    home.packages = [ pkgs._1password-cli ];

    home.file.".local/bin/headlamp-ai" = {
      executable = true;
      text = let
        envFlags = lib.concatStringsSep " " (lib.filter (s: s != "") [
          (mkSecretEnvLine "OPENAI_API_KEY" cfg.aiAssistant.openaiSecretRef)
          (mkSecretEnvLine "ANTHROPIC_API_KEY" cfg.aiAssistant.anthropicSecretRef)
          (mkSecretEnvLine "AZURE_OPENAI_API_KEY" cfg.aiAssistant.azureOpenAISecretRef)
        ] ++ (lib.mapAttrsToList (n: v: "--env ${n}=${v}") cfg.aiAssistant.extraEnv));
      in ''
        #!/usr/bin/env bash
        set -euo pipefail
        exec op run ${envFlags} -- headlamp --disable-gpu --watch-plugins-changes "$@"
      '';
    };

    # Optional desktop launcher that uses the wrapper
    xdg.desktopEntries = lib.mkIf cfg.aiAssistant.createDesktopEntry {
      headlamp-ai = {
        name = "Headlamp (AI)";
        comment = "Kubernetes UI with AI Assistant";
        exec = "${config.home.homeDirectory}/.local/bin/headlamp-ai %U";
        terminal = false;
        type = "Application";
        icon = "headlamp";
        categories = [ "Development" "System" ];
      };
    };
  };
}
