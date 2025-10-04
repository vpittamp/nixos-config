{ config, pkgs, lib, ... }:

{
  # opnix - Declarative 1Password secret management for Home Manager
  # Secrets are fetched during home-manager activation and stored in tmpfs
  # with restricted permissions. They never touch the Nix store.

  opnix.secrets = {
    # Anthropic API key for Claude Code, Avante.nvim, and other AI tools
    anthropic-api-key = {
      source = "op://CLI/ANTHROPIC_API_KEY/credential";
    };

    # GitHub Personal Access Token for gh CLI, git operations, and API access
    github-token = {
      source = "op://CLI/github.com/credential";
    };

    # OpenAI API key for ChatGPT integrations and AI tools
    openai-api-key = {
      source = "op://CLI/OPENAI_API_KEY/credential";
    };

    # Gemini API key for Google AI tools
    gemini-api-key = {
      source = "op://CLI/GEMINI_API_KEY/credential";
    };

    # Tailscale auth key for automated device registration
    # tailscale-auth-key = {
    #   source = "op://Personal/Tailscale/auth-key";
    # };

    # NPM publish token for package publishing
    # npm-token = {
    #   source = "op://Personal/NPM/token";
    # };

    # Docker Hub credentials
    # docker-password = {
    #   source = "op://Personal/Docker Hub/password";
    # };
  };

  # Configure applications to use the secrets
  # Secrets are available at: config.opnix.secrets.<name>.path

  # NOTE: The secrets will be fetched and activated when you run:
  # sudo nixos-rebuild switch --flake .#hetzner
  #
  # They will be stored in tmpfs at runtime (e.g., /run/user/1000/opnix/secrets/)
  # with restricted permissions (mode 0600, owned by your user)

  # To use secrets in shell scripts or environment variables:
  # 1. Reference the path: ${config.opnix.secrets.<name>.path}
  # 2. Read at runtime: $(cat ${config.opnix.secrets.<name>.path})
  #
  # Examples are provided below but commented out to avoid conflicts
  # with existing configurations. Uncomment and customize as needed.

  # Example: Environment variables for shells
  # home.sessionVariables = {
  #   # Anthropic API key for Claude-powered tools
  #   ANTHROPIC_API_KEY = lib.mkDefault "$(cat ${config.opnix.secrets.anthropic-api-key.path} 2>/dev/null || echo '')";
  #   AVANTE_ANTHROPIC_API_KEY = lib.mkDefault "$(cat ${config.opnix.secrets.anthropic-api-key.path} 2>/dev/null || echo '')";
  #
  #   # GitHub token for gh CLI and git operations
  #   GITHUB_TOKEN = lib.mkDefault "$(cat ${config.opnix.secrets.github-token.path} 2>/dev/null || echo '')";
  # };

  # Example: GitHub CLI configuration (already configured in git.nix)
  # programs.gh.settings.git_protocol = "https";

  # Example: Git credential helper (already configured in git.nix)
  # programs.git.extraConfig.credential."https://github.com".helper =
  #   "!f() { test \"$1\" = get && echo \"password=$(cat ${config.opnix.secrets.github-token.path})\"; }; f";

  # Notes on secret paths:
  # - Secrets are stored in tmpfs (RAM) at paths like: /run/user/1000/opnix/secrets/<name>
  # - They are only readable by your user (mode 0600)
  # - They are automatically cleaned up on logout/reboot
  # - They are never written to the Nix store
  # - Use $(cat ${config.opnix.secrets.<name>.path}) to reference in shell commands
  # - Use lib.fileContents config.opnix.secrets.<name>.path for static file content
}
