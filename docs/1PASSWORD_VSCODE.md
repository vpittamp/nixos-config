# 1Password VS Code Integration Guide

## Overview
This document explains how to use 1Password with VS Code for secure secret management in your development workflow.

## Features Configured

### 1. Automatic Secret Detection
VS Code will automatically detect potential secrets in:
- `.env` files
- `config.json` files
- `settings.json` files  
- `*.config.js` and `*.config.ts` files

When a potential secret is detected, you'll see a CodeLens prompt to save it to 1Password.

### 2. Secret References
Instead of hardcoding secrets, use 1Password secret references:

```bash
# .env file example
DATABASE_PASSWORD="op://Development/Database/password"
API_KEY="op://Personal/MyApp/api_key"
GITHUB_TOKEN="op://Developer/GitHub/personal_access_token"
```

### 3. Using Secret References in Code

#### JavaScript/TypeScript
```javascript
// Load secret using 1Password CLI
const apiKey = process.env.API_KEY; // Will be resolved from 1Password

// Or use direct CLI call
const { execSync } = require('child_process');
const secret = execSync('op read "op://vault/item/field"').toString().trim();
```

#### Python
```python
import os
import subprocess

# From environment
api_key = os.environ.get('API_KEY')

# Direct CLI call
secret = subprocess.check_output(['op', 'read', 'op://vault/item/field']).decode().strip()
```

### 4. VS Code Commands
Access these via Command Palette (Ctrl+Shift+P):

- **1Password: Save in 1Password** - Save selected text as a secret
- **1Password: Generate Password** - Create a new secure password
- **1Password: Open in 1Password** - Open the current secret in 1Password app
- **1Password: Insert Secret Reference** - Insert a reference to an existing secret

### 5. Keyboard Shortcuts Configured
- `Ctrl+Alt+O` - Open in 1Password
- `Ctrl+Alt+G` - Generate password
- `Ctrl+Alt+S` - Save in 1Password

### 6. Context Menu Integration
Right-click on any text to see 1Password options:
- Save to 1Password
- Generate Password
- Insert Secret Reference

## Best Practices

### 1. Never Commit Real Secrets
Always use secret references:
```bash
# BAD - Real secret
DATABASE_PASSWORD="myActualPassword123!"

# GOOD - Secret reference
DATABASE_PASSWORD="op://Production/Database/password"
```

### 2. Use Descriptive Vault Structure
Organize your secrets logically:
```
op://[Vault]/[Item]/[Field]

Examples:
op://Development/PostgreSQL/password
op://Production/AWS/access_key_id
op://Personal/GitHub/personal_access_token
```

### 3. Loading Secrets at Runtime

Create a `.env.example` with references:
```bash
# .env.example
DATABASE_URL="op://Development/Database/connection_string"
REDIS_PASSWORD="op://Development/Redis/password"
JWT_SECRET="op://Development/API/jwt_secret"
```

Then use `op run` to inject secrets:
```bash
# Run with injected secrets
op run --env-file=".env.example" -- npm start
op run --env-file=".env.example" -- python app.py
```

### 4. Team Collaboration
Share secret references in your repository:
- Commit `.env.example` files with references
- Never commit `.env` files with actual values
- Document which vault/items team members need access to

## Testing the Integration

### 1. Test Secret Detection
Create a test file `test-secrets.env`:
```bash
# This should trigger secret detection
MY_PASSWORD=thisIsATestPassword123!
API_KEY=sk_test_abcdef123456789
```

VS Code should show CodeLens prompts to save these to 1Password.

### 2. Test Secret References
```bash
# Create a reference
echo 'TEST_SECRET="op://Private/Test/password"' > test-ref.env

# Resolve it
op run --env-file="test-ref.env" -- printenv TEST_SECRET
```

### 3. Test in Terminal
```bash
# Verify 1Password CLI is working
op vault list

# Create a test secret
echo "myTestValue" | op item create --category=password --title="VSCode Test" --vault="Private" password="$(cat -)"

# Read it back
op read "op://Private/VSCode Test/password"
```

## Troubleshooting

### Issue: Extension not detecting secrets
- Ensure file matches configured patterns in settings
- Check that `1password.detection.enableAutomaticDetection` is true
- Restart VS Code after configuration changes

### Issue: Can't unlock secrets inline
- Verify 1Password desktop app is running
- Check CLI integration: `op whoami`
- Re-authenticate: `eval $(op signin)`

### Issue: Secret references not resolving
- Ensure you're using `op run` to execute your application
- Verify the reference format: `op://vault/item/field`
- Check vault and item names for typos (case-sensitive)

## Security Notes

1. **Never log secret values** - Use references in logs
2. **Rotate secrets regularly** - 1Password can generate new values
3. **Use separate vaults** for dev/staging/production
4. **Enable 2FA** on your 1Password account
5. **Review access logs** in 1Password regularly

## Additional Resources

- [1Password CLI Documentation](https://developer.1password.com/docs/cli)
- [VS Code Extension Documentation](https://developer.1password.com/docs/vscode)
- [Secret References Guide](https://developer.1password.com/docs/cli/secrets-references)
- [op run Documentation](https://developer.1password.com/docs/cli/secrets-scripts)

---
*Last updated: 2025-09 with comprehensive VS Code integration*