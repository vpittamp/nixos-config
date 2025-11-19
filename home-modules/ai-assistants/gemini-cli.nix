{ config, pkgs, lib, pkgs-unstable ? pkgs, ... }:

let
  chromiumBin = "${pkgs.chromium}/bin/chromium";
in
{
  # Gemini CLI - Google's Gemini AI in terminal (using native home-manager module with unstable package)
  programs.gemini-cli = {
    enable = true;
    package = pkgs-unstable.gemini-cli or pkgs.gemini-cli;  # Use unstable if available, fallback to stable

    # Default model to use (Gemini 2.5 Pro - upgrade to 3.0 when nixpkgs updates to v0.16.0+)
    defaultModel = "gemini-2.5-pro";

    # Settings for gemini-cli
    settings = {
      theme = "Default";
      vimMode = false;
      preferredEditor = "nvim";
      autoAccept = false;

      # Authentication - use OAuth personal for free tier access
      security = {
        auth = {
          selectedType = "oauth-personal";
        };
      };

      # MCP Servers configuration
      mcpServers = {
        # Chrome DevTools MCP server for browser debugging and performance analysis
        chrome-devtools = {
          command = "npx";
          args = [
            "-y"
            "chrome-devtools-mcp@latest"
            "--isolated"
            "--headless"  # Run without GUI (learned from Codex fix)
            "--executablePath"
            chromiumBin
          ];
        };

        # Playwright MCP server for reliable browser automation
        playwright = {
          command = "npx";
          args = [
            "-y"
            "@playwright/mcp@latest"
            "--isolated"
            "--browser"
            "chromium"
            "--executable-path"
            chromiumBin
          ];
          env = {
            PLAYWRIGHT_SKIP_CHROMIUM_DOWNLOAD = "true";
            PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
          };
        };
      };
    };

    # Custom commands for common workflows
    commands = {
      # Git commit helper
      "commit" = {
        description = "Generate a conventional commit message from staged changes";
        prompt = ''
          Analyze the git diff of staged changes and generate a conventional commit message.
          Use the format: <type>(<scope>): <description>
          
          Types: feat, fix, docs, style, refactor, test, chore
          
          Git diff:
          $(git diff --cached)
          
          Additional context: {{args}}
        '';
      };
      
      # NixOS helper
      "nix-help" = {
        description = "Get help with NixOS configurations and commands";
        prompt = ''
          You are a NixOS expert. Help with the following NixOS-related question or task:
          {{args}}
          
          Context:
          - System: NixOS with home-manager
          - Flake-based configuration in /etc/nixos
          - Using unstable nixpkgs channel
          - Container-based development environment
        '';
      };
      
      # Kubernetes/CDK8s helper
      "k8s" = {
        description = "Help with Kubernetes and CDK8s tasks";
        prompt = ''
          You are a Kubernetes and CDK8s expert. Help with the following:
          {{args}}
          
          Context:
          - Using CDK8s with TypeScript
          - ArgoCD for GitOps
          - Kind cluster for local development
          - VClusters for multi-tenancy
          - Backstage for developer portal
        '';
      };
      
      # Code review
      "review" = {
        description = "Review code changes and provide feedback";
        prompt = ''
          Review the following code changes and provide constructive feedback:
          
          Focus on:
          1. Code quality and best practices
          2. Potential bugs or issues
          3. Security concerns
          4. Performance implications
          5. Maintainability
          
          Changes to review: {{args}}
        '';
      };
      
      # Documentation generator
      "docs" = {
        description = "Generate or improve documentation";
        prompt = ''
          Generate clear, comprehensive documentation for: {{args}}
          
          Include:
          - Purpose and overview
          - Usage examples
          - Configuration options
          - Common issues and solutions
          - Best practices
          
          Use Markdown format with proper headings.
        '';
      };
      
      # TypeScript helper
      "ts" = {
        description = "Help with TypeScript code and CDK8s constructs";
        prompt = ''
          You are a TypeScript and CDK8s expert. Help with the following:
          {{args}}
          
          Context:
          - TypeScript for CDK8s applications
          - Modern TypeScript features and patterns
          - Type safety and best practices
          - CDK8s construct development
        '';
      };
      
      # Troubleshooting assistant
      "debug" = {
        description = "Help debug issues in the development environment";
        prompt = ''
          Help debug the following issue:
          {{args}}
          
          Approach:
          1. Identify the problem clearly
          2. List possible causes
          3. Suggest diagnostic steps
          4. Provide potential solutions
          5. Include relevant commands or code fixes
        '';
      };
      
      # Explain command or concept
      "explain" = {
        description = "Explain a command, concept, or technology";
        prompt = ''
          Provide a clear, concise explanation of: {{args}}
          
          Include:
          - What it is and its purpose
          - How it works
          - Common use cases
          - Examples if applicable
          - Related concepts or tools
        '';
      };
      
      # Security audit
      "security" = {
        description = "Perform security review of code or configuration";
        prompt = ''
          Perform a security audit of the following:
          {{args}}
          
          Check for:
          1. Exposed secrets or credentials
          2. Insecure configurations
          3. Potential vulnerabilities
          4. Best practice violations
          5. Compliance issues
          
          Provide specific recommendations for improvements.
        '';
      };
      
      # Performance optimization
      "optimize" = {
        description = "Suggest performance optimizations";
        prompt = ''
          Analyze and suggest performance optimizations for:
          {{args}}
          
          Consider:
          1. Algorithm efficiency
          2. Resource utilization
          3. Caching opportunities
          4. Code optimization
          5. Configuration tuning
          
          Provide specific, actionable recommendations.
        '';
      };
    };
  };
}