{ config, pkgs, lib, ... }:

{
  # GitHub CLI configuration
  programs.gh = {
    enable = true;
    package = pkgs.gh;
    
    # Git credential helper configuration
    gitCredentialHelper = {
      enable = true;
      hosts = [
        "https://github.com"
        "https://gist.github.com"
      ];
    };
    
    # General settings
    settings = {
      # Use SSH for git operations
      git_protocol = "ssh";
      
      # Enable interactive prompts
      prompt = "enabled";
      
      # Set default editor (will use system default if not specified)
      editor = "";
      
      # Browser settings
      browser = "";
      
      # Pager settings
      pager = "";
      
      # HTTP settings
      http_unix_socket = "";
      
      # Useful aliases for common operations
      aliases = {
        # Pull request shortcuts
        co = "pr checkout";
        pv = "pr view";
        pc = "pr create";
        pl = "pr list";
        pm = "pr merge";
        
        # Issue shortcuts
        il = "issue list";
        iv = "issue view";
        ic = "issue create";
        
        # Repo shortcuts
        rv = "repo view";
        rc = "repo clone";
        rf = "repo fork";
        
        # Workflow shortcuts
        wl = "workflow list";
        wv = "workflow view";
        wr = "workflow run";
        
        # Release shortcuts
        rl = "release list";
        rv = "release view";
        rc = "release create";
      };
    };
    
    # Extensions (uncomment to add)
    # extensions = with pkgs; [
    #   gh-dash      # Dashboard for pull requests and issues
    #   gh-eco       # Explore the ecosystem
    #   gh-markdown-preview  # Preview markdown files
    # ];
    
    # Host-specific configuration
    hosts = {
      "github.com" = {
        user = "vpittamp";
        # The gh CLI will handle authentication via gh auth login
        # No need to store tokens here
      };
    };
  };
}