# opnix - Declarative 1Password Secret Management

## Overview

opnix provides declarative secret management for NixOS and Home Manager using 1Password. Secrets are fetched during activation and stored securely in tmpfs (RAM) with restricted permissions. They **never** touch the Nix store.

## Current Configuration

opnix is integrated into your Home Manager configuration:
- **Flake input**: `github:mrjones2014/opnix`
- **Module**: `home-modules/tools/opnix-secrets.nix`
- **Imported in**: `home-modules/profiles/base-home.nix`

## How It Works

1. **Declarative**: Define secrets in `opnix-secrets.nix` using `op://` syntax
2. **Activation**: When home-manager activates, opnix fetches secrets via `op` CLI
3. **Storage**: Secrets are stored in tmpfs at `/run/user/1000/opnix/secrets/<name>`
4. **Permissions**: Files are mode 0600 (only readable by your user)
5. **Lifecycle**: Secrets are automatically cleaned up on logout/reboot

## Requirements

- ✅ 1Password desktop app installed and running
- ✅ 1Password CLI (`op`) integrated with desktop app
- ✅ Authenticated session (via desktop app)

Check integration: Settings > Developer > "Integrate with 1Password CLI"

## Defining Secrets

Edit `home-modules/tools/opnix-secrets.nix`:

```nix
opnix.secrets = {
  # Example: Anthropic API key
  anthropic-api-key = {
    source = "op://Personal/Anthropic API Key/credential";
  };

  # Example: GitHub token
  github-token = {
    source = "op://Personal/GitHub Personal Access Token/credential";
  };
};
```

### op:// Syntax

Format: `op://VAULT/ITEM/FIELD`

- **VAULT**: Name of your 1Password vault (e.g., "Personal", "Work")
- **ITEM**: Name of the item in 1Password
- **FIELD**: Field to fetch (e.g., "credential", "password", "username", "api_key")

Find your item and field names:
```bash
op item list --vault Personal
op item get "GitHub Personal Access Token" --format json | jq '.fields'
```

## Using Secrets in Configuration

### Option 1: Environment Variables

```nix
home.sessionVariables = {
  ANTHROPIC_API_KEY = "$(cat ${config.opnix.secrets.anthropic-api-key.path})";
  GITHUB_TOKEN = "$(cat ${config.opnix.secrets.github-token.path})";
};
```

### Option 2: Shell Scripts

```nix
home.file.".local/bin/deploy.sh" = {
  text = ''
    #!/usr/bin/env bash
    # Read secret at runtime
    TOKEN=$(cat ${config.opnix.secrets.github-token.path})
    curl -H "Authorization: token $TOKEN" https://api.github.com/user
  '';
  executable = true;
};
```

### Option 3: Git Credentials

```nix
programs.git.extraConfig = {
  credential."https://github.com" = {
    helper = "!f() {
      test \"$1\" = get && echo \"password=$(cat ${config.opnix.secrets.github-token.path})\"
    }; f";
  };
};
```

### Option 4: VSCode Settings (via activation script)

```nix
home.activation.updateVSCodeSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
  VSCODE_SETTINGS="$HOME/.config/Code/User/settings.json"
  if [ -f "$VSCODE_SETTINGS" ]; then
    TOKEN=$(cat ${config.opnix.secrets.github-token.path})
    jq --arg token "$TOKEN" '.["github.token"] = $token' \
      "$VSCODE_SETTINGS" > "$VSCODE_SETTINGS.tmp"
    mv "$VSCODE_SETTINGS.tmp" "$VSCODE_SETTINGS"
  fi
'';
```

## Opportunities for Automation

### Currently Defined Secrets

Your configuration includes:
- ✅ `anthropic-api-key` - For Claude Code, Avante.nvim, AI tools
- ✅ `github-token` - For gh CLI, git operations, GitHub API

### Potential Additional Secrets

Uncomment in `opnix-secrets.nix` or add new ones:

```nix
opnix.secrets = {
  # OpenAI for ChatGPT integrations
  openai-api-key = {
    source = "op://Personal/OpenAI API Key/credential";
  };

  # Tailscale for automated device registration
  tailscale-auth-key = {
    source = "op://Personal/Tailscale/auth-key";
  };

  # NPM for package publishing
  npm-token = {
    source = "op://Personal/NPM/token";
  };

  # Docker Hub credentials
  docker-password = {
    source = "op://Personal/Docker Hub/password";
  };

  # ArgoCD admin password
  argocd-password = {
    source = "op://Personal/ArgoCD/password";
  };

  # AWS credentials
  aws-access-key = {
    source = "op://Personal/AWS/access_key";
  };
  aws-secret-key = {
    source = "op://Personal/AWS/secret_key";
  };
};
```

### Integration Ideas

1. **Claude Code CLI**: Set `ANTHROPIC_API_KEY` automatically
   ```nix
   home.sessionVariables.ANTHROPIC_API_KEY =
     "$(cat ${config.opnix.secrets.anthropic-api-key.path})";
   ```

2. **Neovim Avante Plugin**: Auto-configure API key
   ```nix
   xdg.configFile."nvim/lua/secrets.lua".text = ''
     vim.env.AVANTE_ANTHROPIC_API_KEY =
       vim.fn.system('cat ${config.opnix.secrets.anthropic-api-key.path}'):gsub('%s+', '')
   '';
   ```

3. **GitHub CLI**: Authenticate automatically
   ```nix
   programs.gh.settings = {
     git_protocol = "https";
   };
   home.sessionVariables.GITHUB_TOKEN =
     "$(cat ${config.opnix.secrets.github-token.path})";
   ```

4. **NPM Publishing**: Auto-login
   ```nix
   home.file.".npmrc".text = ''
     //registry.npmjs.org/:_authToken=$(cat ${config.opnix.secrets.npm-token.path})
   '';
   ```

5. **Docker Hub**: Auto-login on activation
   ```nix
   home.activation.dockerLogin = lib.hm.dag.entryAfter ["writeBoundary"] ''
     if command -v docker &>/dev/null; then
       cat ${config.opnix.secrets.docker-password.path} | \
         docker login --username vpittamp --password-stdin
     fi
   '';
   ```

6. **Tailscale**: Auto-authenticate new devices
   ```nix
   home.activation.tailscaleAuth = lib.hm.dag.entryAfter ["writeBoundary"] ''
     if command -v tailscale &>/dev/null && ! tailscale status &>/dev/null; then
       sudo tailscale up --authkey="$(cat ${config.opnix.secrets.tailscale-auth-key.path})"
     fi
   '';
   ```

## Activation

After modifying secrets, rebuild:

```bash
sudo nixos-rebuild switch --flake .#hetzner
```

opnix will:
1. Authenticate via your 1Password desktop app session
2. Fetch each secret using `op read "op://..."`
3. Write secrets to tmpfs with restricted permissions
4. Make them available to your applications

## Debugging

### Check if secrets are available:

```bash
ls -la /run/user/1000/opnix/secrets/
cat /run/user/1000/opnix/secrets/anthropic-api-key
```

### Check 1Password CLI authentication:

```bash
op account list
op whoami
```

### Test secret retrieval manually:

```bash
op read "op://Personal/Anthropic API Key/credential"
```

### Check opnix logs:

```bash
journalctl --user -u home-manager-vpittamp.service | grep opnix
```

## Security Considerations

### ✅ Secure Practices

- Secrets stored in tmpfs (RAM), never written to disk
- File permissions: 0600 (user-only read/write)
- Secrets never appear in Nix store
- Automatic cleanup on logout/reboot
- Uses your authenticated 1Password session

### ⚠️ Limitations

- Secrets available to any process running as your user
- If your user account is compromised, secrets are exposed
- Requires 1Password desktop app to be running
- For system services, use service accounts instead

## Comparison: opnix vs op CLI vs 1Password Extension

| Feature | opnix | op CLI | 1Password Extension |
|---------|-------|--------|---------------------|
| Declarative config | ✅ Yes | ❌ No | ❌ No |
| Auto-fetch on rebuild | ✅ Yes | ❌ Manual | ❌ Manual |
| Nix-native | ✅ Yes | ❌ No | ❌ No |
| VSCode integration | ⚠️ Via config | ❌ No | ✅ Yes |
| Shell integration | ✅ Yes | ✅ Yes | ❌ No |
| System services | ✅ Yes (with service account) | ⚠️ Limited | ❌ No |

## Reference

- [opnix GitHub](https://github.com/mrjones2014/opnix)
- [1Password CLI Reference](https://developer.1password.com/docs/cli/reference)
- [1Password Secret References](https://developer.1password.com/docs/cli/secret-reference-syntax)
