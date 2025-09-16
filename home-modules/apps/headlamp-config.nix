# Headlamp Configuration with AI Assistant and 1Password Integration
{ config, lib, pkgs, ... }:

{
  programs.headlamp = {
    enable = true;
    installPlugins = true;  # Install AI Assistant and External Secrets Operator plugins
    
    aiAssistant = {
      # Configure 1Password secret references for API keys
      # These will be injected when launching Headlamp via the AI desktop entry
      
      # OpenAI API Key for AI Assistant plugin
      openaiSecretRef = "op://Personal/OpenAI API Key/credential";
      
      # Anthropic API Key for Claude integration (if available)
      anthropicSecretRef = "op://Personal/Anthropic API Key/credential";
      
      # Azure OpenAI (optional, uncomment if needed)
      # azureOpenAISecretRef = "op://Work/Azure OpenAI/api_key";
      
      # Create desktop entry that launches Headlamp with API keys from 1Password
      createDesktopEntry = true;
      
      # Additional environment variables if needed
      extraEnv = {
        # Add any additional environment variables here
        # AZURE_OPENAI_ENDPOINT = "op://Work/Azure OpenAI/endpoint";
      };
    };
  };
}