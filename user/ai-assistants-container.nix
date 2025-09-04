# Container-compatible AI assistant configurations
# Simplified versions that work without npm-package complexity
{ config, pkgs, lib, ... }:

{
  # Install available AI assistant tools and their dependencies
  home.packages = with pkgs; [
    # AI pair programming assistant
    aider-chat          # Works with Claude, GPT-4, and other models
    
    # Development tools for AI workflows
    python311           # Python for AI scripts
    python311Packages.pip # Package installer for Python
    python311Packages.requests # HTTP library for API calls
    python311Packages.pyyaml # YAML support
    python311Packages.rich # Rich terminal output
    
    # Node.js for JavaScript-based AI tools
    nodejs_22
    yarn
    
    # Supporting tools
    gh                  # GitHub CLI
    jq                  # JSON processor
    yq-go              # YAML processor
    httpie             # HTTP client
    curl               # HTTP client
    websocat           # WebSocket client for real-time AI tools
    
    # Development environment
    direnv             # Auto-load environment variables
    git                # Version control
  ];
  
  # Shell aliases for AI tools
  programs.bash.shellAliases = {
    # AI assistant shortcuts
    ai = "aider";
    
    # Claude with aider
    claude = "aider --model claude-3-opus-20240229";
    claude-sonnet = "aider --model claude-3-5-sonnet-20240620";
    
    # GPT with aider
    gpt4 = "aider --model gpt-4";
    gpt4o = "aider --model gpt-4o";
    
    # Setup helpers
    ai-setup = "python3 ~/.config/ai-assistants/examples/setup_ai_libs.py";
    ai-keys = "echo 'Set API keys: export ANTHROPIC_API_KEY=... export OPENAI_API_KEY=... export GOOGLE_API_KEY=...'";
    
    # Quick API test commands
    api = "http";
    jsonpp = "jq '.'";
    yamlpp = "yq eval '.' -";
  };
  
  # Environment variables for AI tools (set API keys at runtime)
  home.sessionVariables = {
    # Editor for AI tools
    EDITOR = lib.mkDefault "nvim";
    
    # AI tool paths
    CLAUDE_CONFIG_DIR = "$HOME/.config/claude";
    GEMINI_CONFIG_DIR = "$HOME/.config/gemini";
    
    # Browser for web automation
    PUPPETEER_EXECUTABLE_PATH = "${pkgs.chromium}/bin/chromium";
    
    # Python path for AI libraries
    PYTHONPATH = lib.mkForce "";  # Let Python manage its own paths
  };
  
  # Create configuration directories
  home.file.".config/claude/.keep".text = "";
  home.file.".config/gemini/.keep".text = "";
  home.file.".config/ai-assistants/.keep".text = "";
  
  # Example configuration templates
  home.file.".config/ai-assistants/README.md".text = ''
    # AI Assistants Configuration
    
    ## Setup Instructions
    
    ### Claude (Anthropic)
    1. Get your API key from https://console.anthropic.com/
    2. Set environment variable: `export ANTHROPIC_API_KEY="your-key-here"`
    3. Use with aider: `aider --model claude-3-opus-20240229`
    
    ### Gemini (Google)
    1. Get your API key from https://makersuite.google.com/app/apikey
    2. Set environment variable: `export GOOGLE_API_KEY="your-key-here"`
    3. Use with Python: See examples in ~/.config/ai-assistants/examples/
    
    ### OpenAI (GPT)
    1. Get your API key from https://platform.openai.com/api-keys
    2. Set environment variable: `export OPENAI_API_KEY="your-key-here"`
    3. Use with aider: `aider --model gpt-4`
    
    ## Available Tools
    
    - **aider**: AI pair programming in terminal
    - **Python libraries**: openai, anthropic, google-generativeai, litellm, langchain
    - **Supporting tools**: gh, jq, yq, httpie, curl, websocat
    
    ## Example Scripts
    
    See ~/.config/ai-assistants/examples/ for example scripts and configurations.
  '';
  
  # Example Python script for installing and using AI APIs
  home.file.".config/ai-assistants/examples/setup_ai_libs.py".text = ''
    #!/usr/bin/env python3
    """
    Setup script for AI libraries - run this to install required packages
    """
    import subprocess
    import sys
    
    packages = [
        "openai",           # OpenAI GPT models
        "anthropic",        # Claude models
        "google-generativeai",  # Gemini models
        "litellm",          # Unified LLM interface
        "langchain",        # LLM application framework
        "chromadb",         # Vector database
        "tiktoken",         # Token counting
    ]
    
    print("Installing AI libraries...")
    for package in packages:
        print(f"Installing {package}...")
        subprocess.run([sys.executable, "-m", "pip", "install", "--user", package])
    
    print("\nInstallation complete!")
    print("\nTo use the libraries, set your API keys:")
    print("  export OPENAI_API_KEY='your-key'")
    print("  export ANTHROPIC_API_KEY='your-key'")
    print("  export GOOGLE_API_KEY='your-key'")
    print("\nThen use 'aider' for AI pair programming or write Python scripts.")
  '';
  
  home.file.".config/ai-assistants/examples/setup_ai_libs.py".executable = true;
  
  # LiteLLM configuration for unified LLM interface
  home.file.".config/ai-assistants/litellm_config.yaml".text = ''
    # LiteLLM Configuration
    # Use with: litellm --config ~/.config/ai-assistants/litellm_config.yaml
    
    model_list:
      - model_name: gpt-4
        litellm_params:
          model: gpt-4
          api_key: os.environ/OPENAI_API_KEY
      
      - model_name: claude
        litellm_params:
          model: claude-3-opus-20240229
          api_key: os.environ/ANTHROPIC_API_KEY
      
      - model_name: gemini
        litellm_params:
          model: gemini/gemini-pro
          api_key: os.environ/GOOGLE_API_KEY
  '';
}