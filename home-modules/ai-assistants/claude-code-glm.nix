# Home Manager configuration for GLM Coding Plan with Claude Code
# Sets up a separate `claude-glm` command with its own isolated config in ~/.claude-glm
{ config, pkgs, lib, inputs, pkgs-unstable ? pkgs, ... }:

let
  repoRoot = ../../.;

  # z.ai's model catalogue is authoritative: `curl https://api.z.ai/api/paas/v4/models`.
  #
  #   glm-5.3-flash  320B-A18B natively multimodal MoE, 1.31M context,
  #                  131k max output. Flash-tier price, GLM-5 class quality.
  #   glm-5.3        the full model; slower and dearer, same 131k output cap.
  #
  # Written bare, without the `[1m]` suffix these vars used to carry. That
  # suffix is a Claude Code convention for a 1M-context variant, not part of
  # any model id — the client appends it itself once CLAUDE_CODE_AUTO_COMPACT_WINDOW
  # is 1000000, and strips it again before the request. z.ai's API rejects it
  # if it ever reaches the wire (`1214 modelCode: does not exist`), so the bare
  # id is the one that is true at both ends.
  defaultModel = "glm-5.3-flash";
  proModel = "glm-5.3";

  # Static, secret-free: the only sensitive value is an `op://` reference that
  # `op run` resolves at launch. Living in the store means no mktemp to leak.
  glmEnvFile = pkgs.writeText "claude-glm.env" ''
    ANTHROPIC_AUTH_TOKEN="op://hub-eso/ZAI-API-KEY/password"
    ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic"
    CLAUDE_CODE_AUTO_COMPACT_WINDOW="1000000"
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1"
    API_TIMEOUT_MS="3000000"
  '';

  # Wrapper around the base `claude` binary that points it at z.ai and keeps its
  # configuration in ~/.claude-glm. `CLAUDE_GLM_MODEL` overrides the model for a
  # single run, so any id in the catalogue is reachable without a rebuild.
  #
  # The model is selected with `--model`, NOT with ANTHROPIC_DEFAULT_*_MODEL.
  # Those three vars are inert here: with claude-code 2.1.247 a deliberately
  # bogus value in all three still produces a normal answer, so nothing they
  # name reaches the wire. `--model` does — a bogus value there comes straight
  # back as z.ai's `1214 modelCode: does not exist`. Without it the CLI sends
  # its own built-in Claude id and z.ai silently serves whatever that alias maps
  # to today (`claude-3-5-sonnet-20241022` currently resolves to glm-5.3-flash,
  # and `glm-4.5-air` resolves to glm-4.7), which is a default nobody here
  # chose. The flag is passed before "$@" so an explicit `claude-glm --model X`
  # still wins.
  mkGlmWrapper = { name, model }: pkgs.writeShellScriptBin name ''
    export CLAUDE_DIR="$HOME/.claude-glm"
    if command -v op >/dev/null 2>&1 && op account list >/dev/null 2>&1; then
      GLM_MODEL="''${CLAUDE_GLM_MODEL:-${model}}"

      # Run using op run to dynamically inject the API key.
      # We disable secret masking to ensure the command retains its TTY connection.
      # Use the final packaged/wrapped binary from the base configuration to preserve MCP configs.
      exec op run --no-masking --env-file="${glmEnvFile}" -- "${config.programs.claude-code.finalPackage}/bin/claude" --model "$GLM_MODEL" "$@"
    else
      # No key available: fall through to stock Claude Code rather than failing.
      # The GLM model vars are deliberately not exported on this path — they
      # would point api.anthropic.com at model ids it does not have.
      echo "Warning: 1Password not authenticated/installed. GLM API key cannot be loaded." >&2
      exec "${config.programs.claude-code.finalPackage}/bin/claude" "$@"
    fi
  '';

  # Settings for the GLM variant. Inherits the base settings but drops any
  # `model` pin: the wrappers pass `--model` explicitly, and a settings pin
  # naming an Anthropic alias (this used to be claude-3-5-sonnet-20241022) only
  # obscures which GLM model z.ai ends up serving.
  glmSettings = builtins.removeAttrs config.programs.claude-code.settings [ "model" ];

  # Resolve shared skills for the GLM environment
  sharedSkillsDir = repoRoot + "/shared-skills";
  sharedSkillEntries = if builtins.pathExists sharedSkillsDir then builtins.readDir sharedSkillsDir else {};
  sharedSkillDirs = lib.filterAttrs (_: t: t == "directory" || t == "symlink") sharedSkillEntries;
  sharedSkillHomeFiles = lib.mapAttrs'
    (name: _:
      lib.nameValuePair ".claude-glm/skills/${name}" {
        source = sharedSkillsDir + "/${name}";
        recursive = true;
        force = true;
      }
    )
    sharedSkillDirs;
in
{
  # Install the wrappers. Both share ~/.claude-glm, so skills, plugins, and
  # settings are identical — only the model differs.
  home.packages = [
    (mkGlmWrapper { name = "claude-glm"; model = defaultModel; })
    (mkGlmWrapper { name = "claude-glm-pro"; model = proModel; })
  ];

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
