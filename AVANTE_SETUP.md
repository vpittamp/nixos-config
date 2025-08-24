# Avante.nvim Setup with Claude Integration

## Overview
Avante.nvim is configured to use Claude (Anthropic) as the AI provider for code assistance within Neovim.

## API Key Setup

### Option 1: Environment Variable
Set the API key in your shell environment:
```bash
export AVANTE_ANTHROPIC_API_KEY="your-api-key-here"
```

### Option 2: Using 1Password CLI
If you use 1Password, you can retrieve the key dynamically:
```bash
export AVANTE_ANTHROPIC_API_KEY="$(op read 'op://Private/Anthropic API Key/api_key')"
```

### Option 3: Add to NixOS Configuration
Uncomment and set the API key in `/etc/nixos/home-modules/shell/bash.nix`

## Key Bindings

### Avante Commands
- `<leader>aa` - Ask AI (works in normal and visual mode)
- `<leader>ae` - Edit with AI (works in normal and visual mode)
- `<leader>ar` - Refresh Avante
- `<leader>at` - Toggle Avante sidebar

### Diff Navigation
- `co` - Choose ours (current code)
- `ct` - Choose theirs (AI suggestion)
- `ca` - Accept all AI suggestions
- `cb` - Choose both versions
- `cc` - Choose at cursor
- `]x` - Next diff
- `[x` - Previous diff

### Suggestions (when enabled)
- `Alt+l` - Accept suggestion
- `Alt+]` - Next suggestion
- `Alt+[` - Previous suggestion
- `Ctrl+]` - Dismiss suggestion

## Features

### Current Configuration
- **Provider**: Claude 3.5 Sonnet
- **Mode**: Agentic (uses tools for automatic code generation)
- **Auto-suggestions**: Disabled by default (to control costs)
- **Token counting**: Enabled (shows usage)
- **Tool permissions**: Manual approval required

### Complementary Tools
- **claude-code-nvim**: For terminal-based Claude interactions
- **Avante.nvim**: For IDE-like inline editing experience

## Cost Management

### Tips to Control Costs
1. Auto-suggestions are disabled by default
2. Use project-specific `.avante.md` files for custom instructions
3. Monitor token usage (enabled in config)
4. Use the sidebar to review changes before applying

## Project-Specific Instructions

Create an `.avante.md` file in your project root to provide context:

```markdown
# Project Context for Avante

## Technology Stack
- Language: TypeScript
- Framework: React
- Testing: Jest

## Coding Standards
- Use functional components
- Prefer hooks over class components
- Write tests for all new features

## Project-Specific Rules
- Always use absolute imports
- Follow the existing file structure
```

## MCP Hub Integration (Future)

MCP Hub support is planned for centralized management of Model Context Protocol servers.

### Configuration Location
- MCP config: `/etc/nixos/home-modules/mcp-config.json`
- Servers can be added to extend Avante's capabilities

### Available MCP Servers (when configured)
- Filesystem access
- Git operations
- GitHub integration
- Database connections
- Custom tools

## Troubleshooting

### API Key Not Found
Ensure `AVANTE_ANTHROPIC_API_KEY` is set in your environment.

### High Token Usage
- Disable auto-suggestions
- Use more specific prompts
- Clear conversation history regularly

### Performance Issues
- Increase timeout in configuration
- Check network connectivity to Anthropic API

## Best Practices

1. **Use Visual Selection**: Select code before asking questions for better context
2. **Be Specific**: Provide clear instructions for better results
3. **Review Changes**: Always review AI suggestions before applying
4. **Use Project Context**: Maintain `.avante.md` files for consistency
5. **Combine with LSP**: Let LSP handle syntax while AI handles logic

## Integration with Existing Tools

Avante.nvim complements your existing setup:
- **LSP**: For language-specific features
- **claude-code**: For terminal workflows
- **Copilot**: Can be used alongside for different suggestions