# Docker Hub 1Password Integration - Quick Start

## TL;DR

```bash
# 1. Create Docker Hub token in 1Password (one-time setup)
op item create \
  --category="API Credential" \
  --title="Docker Hub Token" \
  --vault="Personal" \
  username="your-dockerhub-username" \
  credential[password]="dckr_pat_xxxxx"

# 2. Login to Docker Hub (in VS Code terminal or any terminal)
docker-login

# 3. Use Docker normally in VS Code
docker build -t username/myapp:latest .
docker push username/myapp:latest
```

## What's Configured

Your NixOS setup now includes:

1. **VS Code Docker Extension** - Already installed (`ms-azuretools.vscode-docker`)
2. **1Password CLI Integration** - Already configured
3. **Shell Functions** - Automatic Docker authentication via 1Password:
   - `docker-login` - Login using 1Password credentials
   - `docker-push <image>` - Build and push with auto-login
   - `docker-pull-auth <image>` - Pull private images with auto-login
   - `docker-auth-status` - Check authentication status
   - `docker-whoami` - Alias for auth status

## How It Works

The integration uses 1Password CLI to securely retrieve your Docker Hub token and automatically authenticate. No passwords stored on disk!

```
VS Code Terminal → docker-login → 1Password CLI → Docker Hub ✓
```

## First-Time Setup

### Step 1: Create Docker Hub Token

1. Go to https://hub.docker.com/settings/security
2. Click "New Access Token"
3. Name it (e.g., "VS Code Development")
4. Set permissions (usually Read & Write)
5. Copy the token (starts with `dckr_pat_`)

### Step 2: Store in 1Password

**Option A: Using 1Password Desktop App (Easiest)**

1. Open 1Password
2. Click "+" → "API Credential"
3. Title: "Docker Hub Token"
4. Username: your Docker Hub username
5. Credential: paste the token from step 1
6. Website: https://hub.docker.com
7. Save to "Personal" vault (or any vault you prefer)

**Option B: Using 1Password CLI**

```bash
op item create \
  --category="API Credential" \
  --title="Docker Hub Token" \
  --vault="Personal" \
  username="your-dockerhub-username" \
  credential[password]="dckr_pat_your_token_here" \
  url="https://hub.docker.com"
```

### Step 3: Test Authentication

```bash
# In VS Code terminal (or any terminal)
docker-login
```

Expected output:

```
🔐 Authenticating to Docker Hub via 1Password...
Login Succeeded
✅ Successfully logged in to Docker Hub as your-username
```

### Step 4: Verify in VS Code

1. Open Docker extension view (Click Docker icon in sidebar)
2. You should see "REGISTRIES" → "docker.io" → your username
3. Right-click on docker.io and choose "Connect Registry" if not already connected

## Daily Usage

### In VS Code Terminal

```bash
# Check if you're logged in
docker-whoami

# Login when needed
docker-login

# Build and push with auto-authentication
docker build -t username/myapp:latest .
docker-push username/myapp:latest

# Pull private images
docker-pull-auth username/private-app:latest
```

### Using Docker Extension UI

1. The Docker extension will use your CLI authentication automatically
2. Right-click images to push directly from VS Code
3. Right-click registries to refresh or connect

### In docker-compose.yml

```yaml
version: "3.8"
services:
  app:
    image: username/myapp:latest
    # Authentication handled automatically if logged in
```

Then in terminal:

```bash
docker-login  # If not already logged in
docker-compose up
```

## Advanced: Using Secret References

For CI/CD or shared projects, use 1Password secret references:

### Create .env.docker

```bash
# Copy template
cp ~/.docker/.env.docker.example .env.docker

# Edit to match your 1Password vault/item
# .env.docker content:
DOCKER_USERNAME="op://Personal/Docker Hub Token/username"
DOCKER_TOKEN="op://Personal/Docker Hub Token/credential"
```

### Use with op run

```bash
# Login using secret references
op run --env-file=.env.docker -- bash -c \
  'echo $DOCKER_TOKEN | docker login -u $DOCKER_USERNAME --password-stdin'

# Or use the convenience function
docker-login-env .env.docker
```

## VS Code Tasks

Create `.vscode/tasks.json` in your project:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Docker: Build and Push",
      "type": "shell",
      "command": "docker-login && docker build -t ${input:imageName} . && docker push ${input:imageName}",
      "problemMatcher": []
    }
  ],
  "inputs": [
    {
      "id": "imageName",
      "type": "promptString",
      "description": "Docker image name (username/repo:tag)"
    }
  ]
}
```

Use with: `Ctrl+Shift+P` → "Tasks: Run Task" → "Docker: Build and Push"

## Troubleshooting

### "Could not retrieve credentials from 1Password"

```bash
# Check if item exists
op item get "Docker Hub Token"

# Verify fields
op item get "Docker Hub Token" --fields username
op item get "Docker Hub Token" --fields credential

# If not found, create it (see Step 2 above)
```

### "unauthorized: incorrect username or password"

Your token might have expired. Generate a new one:

1. Go to https://hub.docker.com/settings/security
2. Delete old token
3. Create new token
4. Update in 1Password (edit the "Docker Hub Token" item)
5. Run `docker-login` again

### VS Code Docker extension shows "Not logged in"

```bash
# Login via terminal first
docker-login

# Restart Docker extension
# Ctrl+Shift+P → "Developer: Reload Window"
```

### "error during connect: Get http://..."

Docker daemon isn't running. Start Docker Desktop or Docker service.

```bash
# Check Docker status
docker version

# On NixOS with Docker installed
sudo systemctl start docker
```

## Security Notes

✅ **Secure**: Token stored in 1Password encrypted vault
✅ **Automatic**: No manual password entry needed
✅ **Auditable**: 1Password logs all credential access
✅ **Rotatable**: Update token in one place, works everywhere

❌ **Don't**: Store tokens in `.env` files (use secret references)
❌ **Don't**: Commit `.docker/config.json` with auth tokens
❌ **Don't**: Share tokens via chat/email

## What's New in Your NixOS Config

After rebuilding your NixOS configuration:

1. ✅ `~/.docker/config.json` - Docker config with BuildKit enabled
2. ✅ `~/.docker/.env.docker.example` - Template for secret references
3. ✅ `docker-login` command - Auto-authentication from 1Password
4. ✅ `docker-push` command - Build and push with auto-auth
5. ✅ `docker-pull-auth` command - Pull private images with auto-auth
6. ✅ `docker-whoami` command - Check authentication status
7. ✅ VS Code Docker extension settings - Optimized for your setup

## Next Steps

1. Create your Docker Hub token → Store in 1Password
2. Run `docker-login` in VS Code terminal
3. Start using Docker with automatic authentication!

For detailed information, see: `/etc/nixos/docs/DOCKER_HUB_1PASSWORD.md`

---

_Quick reference for Docker Hub authentication via 1Password in VS Code_
