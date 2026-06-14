{ config, pkgs, pkgs-unstable, lib, inputs, ... }:

# Antigravity CLI — Google's Gemini-CLI successor.
#
# Background: Google announced Antigravity 2.0 at I/O 2026 (2026-05-19) and is
# sunsetting Gemini CLI for Google AI Pro/Ultra/Free on 2026-06-18.
# https://developers.googleblog.com/an-important-update-transitioning-gemini-cli-to-antigravity-cli/
#
# The CLI is not yet in nixos-unstable; it lives in open nixpkgs PR #522045.
# We consume it via the SHA-pinned `nixpkgs-antigravity-cli` flake input. When
# that PR merges, switch this back to `pkgs.antigravity-cli` and delete the
# input from flake.nix (search for `TODO(antigravity-cli)`).
#
# Minimal scaffold for now — package only. Once we understand the CLI's
# settings surface (likely `~/.config/antigravity/` or similar), follow the
# patterns from claude-code.nix / codex.nix and add:
#   - wrapped binary with OTEL_RESOURCE_ATTRIBUTES and i3pm.* tags
#   - service.name routing in modules/services/grafana-alloy.nix
#   - MLflow experiment ID in configurations/{ryzen,thinkpad,hetzner}.nix
#   - MCP server / extension setup
#   - hooks / skills (Antigravity CLI keeps Agent Skills, Hooks, Subagents)

let
  antigravityCliPackage = pkgs-unstable.antigravity-cli;
in
{
  home.packages = [ antigravityCliPackage ];
}
