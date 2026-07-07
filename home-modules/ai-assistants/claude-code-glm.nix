# Home Manager configuration for GLM Coding Plan with Claude Code
# Sets up a separate `claude-glm` command with its own isolated config in ~/.claude-glm
{ config, pkgs, lib, inputs, pkgs-unstable ? pkgs, ... }:

let
  repoRoot = ../../.;
  baseClaudeCode = inputs.claude-code-nix.packages.${pkgs.system}.claude-code or pkgs-unstable.claude-code or pkgs.claude-code;

  # Define settings specifically for the GLM variant
  # Inherit default settings but override model to target Sonnet (which is mapped to GLM-5.2[1m])
  glmSettings = config.programs.claude-code.settings // {
    model = "claude-3-5-sonnet-20241022";
  };

  # Create a wrapper script `claude-glm` that uses ~/.claude-glm as its configuration directory
  # and injects GLM environment variables via 1Password at runtime
  claudeGlmPackage = pkgs.writeShellScriptBin "claude-glm" ''
    export CLAUDE_DIR="$HOME/.claude-glm"
    if command -v op >/dev/null 2>&1 && op account list >/dev/null 2>&1; then
      ENV_FILE=$(mktemp)
      cat <<'INNER_EOF' > "$ENV_FILE"
ANTHROPIC_AUTH_TOKEN="op://hub-eso/ZAI-API-KEY/password"
ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic"
ANTHROPIC_DEFAULT_HAIKU_MODEL="glm-5.2[1m]"
ANTHROPIC_DEFAULT_SONNET_MODEL="glm-5.2[1m]"
ANTHROPIC_DEFAULT_OPUS_MODEL="glm-5.2[1m]"
CLAUDE_CODE_AUTO_COMPACT_WINDOW="1000000"
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1"
API_TIMEOUT_MS="3000000"
INNER_EOF

      # Run using op run to dynamically inject the API key
      # We disable secret masking to ensure the command retains its TTY connection
      # Use the final packaged/wrapped binary from the base configuration to preserve MCP configs
      exec op run --no-masking --env-file="$ENV_FILE" -- "${config.programs.claude-code.finalPackage}/bin/claude" "$@"
      EXIT_CODE=$?
      rm -f "$ENV_FILE"
      exit $EXIT_CODE
    else
      echo "Warning: 1Password not authenticated/installed. GLM API key cannot be loaded." >&2
      exec "${config.programs.claude-code.finalPackage}/bin/claude" "$@"
    fi
  '';

  # Resolve shared skills for the GLM environment
  sharedSkillsDir = repoRoot + "/shared-skills";
  sharedSkillEntries = if builtins.pathExists sharedSkillsDir then builtins.readDir sharedSkillsDir else {};
  sharedSkillDirs = lib.filterAttrs (_: t: t == "directory" || t == "symlink") sharedSkillEntries;
  sharedSkillHomeFiles = lib.mapAttrs'
    (name: _:
      lib.nameValuePair ".claude-glm/skills/${name}" {
        source = sharedSkillsDir + "/${name}";
        recursive = true;
      }
    )
    sharedSkillDirs;
in
{
  # Install the `claude-glm` wrapper package
  home.packages = [ claudeGlmPackage ];

  # Configure files for the ~/.claude-glm workspace
  home.file = sharedSkillHomeFiles // {
    # LSP plugin for Claude Code (GLM workspace) — provides code intelligence
    ".claude-glm/plugins/nix-lsp/.claude-plugin/plugin.json".text = builtins.toJSON {
      name = "nix-lsp";
      description = "Language servers for Python, TypeScript, Nix, QML, and YAML";
      version = "1.0.0";
    };
    ".claude-glm/plugins/nix-lsp/.lsp.json".text = builtins.toJSON {
      python = {
        command = "${pkgs.pyright}/bin/pyright-langserver";
        args = [ "--stdio" ];
        extensionToLanguage = {
          ".py" = "python";
          ".pyi" = "python";
        };
      };
      typescript = {
        command = "${pkgs.typescript-language-server}/bin/typescript-language-server";
        args = [ "--stdio" ];
        extensionToLanguage = {
          ".ts" = "typescript";
          ".tsx" = "typescriptreact";
          ".js" = "javascript";
          ".jsx" = "javascriptreact";
        };
      };
      nix = {
        command = "${pkgs.nil}/bin/nil";
        args = [];
        extensionToLanguage = {
          ".nix" = "nix";
        };
      };
      qml = {
        command = "${pkgs.kdePackages.qtdeclarative}/bin/qmlls";
        args = [];
        extensionToLanguage = {
          ".qml" = "qml";
        };
      };
      yaml = {
        command = "${pkgs.yaml-language-server}/bin/yaml-language-server";
        args = [ "--stdio" ];
        extensionToLanguage = {
          ".yaml" = "yaml";
          ".yml" = "yaml";
        };
      };
    };
  };

  # Write writable settings file under ~/.claude-glm/settings.json
  home.activation.writableClaudeGlmSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    _src='${pkgs.writeText "claude-glm-settings.json" (builtins.toJSON glmSettings)}'
    _dst="$HOME/.claude-glm/settings.json"
    run ${pkgs.coreutils}/bin/mkdir -p "$HOME/.claude-glm"
    if [ -L "$_dst" ]; then run ${pkgs.coreutils}/bin/rm -f "$_dst"; fi
    run ${pkgs.coreutils}/bin/install -m 0644 "$_src" "$_dst"
  '';

  # Patch scripts in ~/.claude-glm marketplace plugins (NixOS compatibility)
  home.activation.patchClaudeGlmPlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    PLUGIN_CACHE="$HOME/.claude-glm/plugins/cache/claude-code-plugins"
    if [ -d "$PLUGIN_CACHE" ]; then
      run ${pkgs.findutils}/bin/find "$PLUGIN_CACHE" -name "*.sh" -type f \
        -exec ${pkgs.gnused}/bin/sed -i 's|^#!/bin/bash|#!/usr/bin/env bash|' {} \;
    fi
  '';
}
