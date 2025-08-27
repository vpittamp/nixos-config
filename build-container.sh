#!/bin/bash
# Build NixOS containers with unified configuration
# Supports both standard containers and devcontainers

set -e

# Parse command line arguments
MODE="container"  # Default mode
PROFILE=""  # Will be set from arguments or default to "essential" later
OUTPUT_FILE=""
PROJECT_DIR=""

function show_help {
    echo "🔨 NixOS Container Builder"
    echo ""
    echo "Usage:"
    echo "  $0 [OPTIONS] [profile] [output-file]"
    echo ""
    echo "Options:"
    echo "  --devcontainer, -d     Build as devcontainer (requires devcontainer CLI)"
    echo "  --project-dir, -p DIR  Project directory for devcontainer (default: current dir)"
    echo "  --help, -h            Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  LOAD_DOCKER=true       Automatically load container into Docker"
    echo "  DOCKER_TAG=<tag>       Tag the loaded image (e.g., docker.io/user/image:tag)"
    echo "  DOCKER_PUSH=true       Push the tagged image to registry"
    echo "  CONTAINER_SSH_ENABLED=true    Enable SSH server in container"
    echo "  CONTAINER_SSH_PORT=2222       SSH server port (default: 2222)"
    echo "  VSCODE_TUNNEL_ENABLED=true    Enable VS Code tunnel support"
    echo ""
    echo "Profiles:"
    echo "  essential              Core tools only (~275MB)"
    echo "  essential,kubernetes   Core + K8s tools (~600MB)"
    echo "  essential,development  Core + dev tools (~600MB)"
    echo "  full                   All packages (~1GB)"
    echo ""
    echo "Examples:"
    echo "  # Build standard container"
    echo "  $0 essential output.tar.gz"
    echo ""
    echo "  # Build and load into Docker"
    echo "  LOAD_DOCKER=true $0"
    echo ""
    echo "  # Build, load, tag and push"
    echo "  LOAD_DOCKER=true DOCKER_TAG=docker.io/user/image:v1.0 DOCKER_PUSH=true $0"
    echo ""
    echo "  # Build with SSH and VS Code tunnel support"
    echo "  CONTAINER_SSH_ENABLED=true VSCODE_TUNNEL_ENABLED=true $0"
    echo ""
    echo "  # Build devcontainer with full profile"
    echo "  $0 --devcontainer full"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --devcontainer|-d)
            MODE="devcontainer"
            shift
            ;;
        --project-dir|-p)
            PROJECT_DIR="$2"
            shift 2
            ;;
        --help|-h)
            show_help
            ;;
        -*)
            echo "Unknown option: $1"
            show_help
            ;;
        *)
            if [ -z "$PROFILE" ]; then
                PROFILE="$1"
            elif [ -z "$OUTPUT_FILE" ]; then
                OUTPUT_FILE="$1"
            fi
            shift
            ;;
    esac
done

# Don't re-process arguments - they were already handled in the while loop above

# Set default profile if not specified
if [ -z "$PROFILE" ]; then
    PROFILE="essential"
fi

echo "🔨 Building NixOS ${MODE}"
echo "📦 Package profile: $PROFILE"

# Show enabled features
echo "🔧 Features:"
[ "${CONTAINER_SSH_ENABLED:-}" = "true" ] && echo "  ✅ SSH server (port ${CONTAINER_SSH_PORT:-2222})"
[ "${VSCODE_TUNNEL_ENABLED:-}" = "true" ] && echo "  ✅ VS Code tunnel support"
[ "${VSCODE_SERVER_PREINSTALL:-}" = "true" ] && echo "  ✅ VS Code server pre-installed"
[ "${LOAD_DOCKER:-}" = "true" ] && echo "  ✅ Auto-load into Docker"
[ -n "${DOCKER_TAG:-}" ] && echo "  ✅ Docker tag: ${DOCKER_TAG}"
[ "${DOCKER_PUSH:-}" = "true" ] && echo "  ✅ Push to registry"
echo ""

# Set environment variables for the build
export NIXOS_CONTAINER=1
export NIXOS_PACKAGES="$PROFILE"

if [ "$MODE" = "devcontainer" ]; then
    # Build devcontainer
    echo "🐳 Building devcontainer..."
    
    # Set project directory (default to current directory)
    PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
    echo "📁 Project directory: $PROJECT_DIR"
    
    # First build the base NixOS container
    cd /etc/nixos
    CONTAINER_PATH=$(nix build .#container --no-link --print-out-paths)
    
    # Load the container into Docker
    echo "📦 Loading NixOS container into Docker..."
    docker load < "$CONTAINER_PATH" | grep "Loaded image" | cut -d' ' -f3 > /tmp/nixos-image-id
    BASE_IMAGE=$(cat /tmp/nixos-image-id)
    
    # Create devcontainer configuration if it doesn't exist
    DEVCONTAINER_DIR="$PROJECT_DIR/.devcontainer"
    TEMP_DEVCONTAINER=false
    
    if [ ! -f "$DEVCONTAINER_DIR/devcontainer.json" ]; then
        echo "📝 Creating devcontainer configuration..."
        mkdir -p "$DEVCONTAINER_DIR"
        TEMP_DEVCONTAINER=true
        
        # Create devcontainer.json
        cat > "$DEVCONTAINER_DIR/devcontainer.json" << EOF
{
    "name": "NixOS Development Container",
    "image": "nixos-devcontainer:${PROFILE}",
    "features": {},
    "customizations": {
        "vscode": {
            "extensions": [
                "jnoortheen.nix-ide",
                "ms-vscode.cpptools",
                "ms-python.python",
                "ms-azuretools.vscode-docker"
            ],
            "settings": {
                "terminal.integrated.defaultProfile.linux": "bash",
                "terminal.integrated.profiles.linux": {
                    "bash": {
                        "path": "/bin/bash"
                    }
                }
            }
        }
    },
    "mounts": [
        "source=\${localWorkspaceFolder},target=/workspace,type=bind"
    ],
    "workspaceFolder": "/workspace",
    "postCreateCommand": "echo 'Welcome to NixOS devcontainer with profile: ${PROFILE}'",
    "remoteUser": "root"
}
EOF
        
        # Create .env file for environment variables
        cat > "$DEVCONTAINER_DIR/.env" << EOF
NIXOS_PACKAGES=${PROFILE}
NIXOS_CONTAINER=1
EOF
    fi
    
    # Build Docker image for devcontainer
    echo "🏗️  Building devcontainer Docker image..."
    docker tag "$BASE_IMAGE" "nixos-devcontainer:${PROFILE}"
    
    # Clean up temporary files if created but keep devcontainer config
    if [ "$TEMP_DEVCONTAINER" = false ]; then
        echo "ℹ️  Using existing devcontainer configuration"
    else
        echo "✅ Created devcontainer configuration in $DEVCONTAINER_DIR"
    fi
    
    echo ""
    echo "✅ Devcontainer ready: nixos-devcontainer:${PROFILE}"
    echo ""
    echo "To use this devcontainer:"
    echo "  1. Open VS Code in your project: code $PROJECT_DIR"
    echo "  2. Press F1 and run: 'Dev Containers: Reopen in Container'"
    echo ""
    echo "Or use Docker directly:"
    echo "  docker run -it -v $PROJECT_DIR:/workspace nixos-devcontainer:${PROFILE} /bin/bash"
    
else
    # Build standard container
    echo "🏗️  Starting Nix build (this may take a while)..."
    cd /etc/nixos
    
    # Add progress indicator for long build
    (
        while true; do
            echo -n "."
            sleep 5
        done
    ) &
    PROGRESS_PID=$!
    
    # Build the container - use --impure to allow NIXOS_PACKAGES env var
    CONTAINER_PATH=$(NIXOS_PACKAGES="$PROFILE" nix build .#container --impure --no-link --print-out-paths 2>&1 | tail -1)
    
    # Stop progress indicator
    kill $PROGRESS_PID 2>/dev/null || true
    echo ""  # New line after dots
    
    # Check if build succeeded
    if [ ! -f "$CONTAINER_PATH" ]; then
        echo "❌ Build failed. Container path not found: $CONTAINER_PATH"
        exit 1
    fi
    
    # Get container size
    SIZE=$(du -sh "$CONTAINER_PATH" | cut -f1)
    echo "✅ Container built: $CONTAINER_PATH"
    echo "📏 Size: $SIZE"
    
    # Option to load into Docker
    if [ "${LOAD_DOCKER:-}" = "true" ] || [ "${AUTO_LOAD:-}" = "true" ]; then
        echo "📦 Loading container into Docker..."
        
        # Handle both .tar.gz and .tar formats and capture the loaded image name
        if [[ "$CONTAINER_PATH" == *.tar.gz ]]; then
            echo "🔓 Decompressing and loading..."
            LOADED_IMAGE=$(gunzip -c "$CONTAINER_PATH" | docker load 2>&1 | grep "Loaded image" | cut -d: -f2- | tr -d ' ')
            if [ -z "$LOADED_IMAGE" ]; then
                echo "❌ Failed to load container into Docker"
                exit 1
            fi
        else
            LOADED_IMAGE=$(docker load < "$CONTAINER_PATH" 2>&1 | grep "Loaded image" | cut -d: -f2- | tr -d ' ')
            if [ -z "$LOADED_IMAGE" ]; then
                echo "❌ Failed to load container into Docker"
                exit 1
            fi
        fi
        
        echo "📦 Loaded image: $LOADED_IMAGE"
        
        # Tag the image if requested
        if [ -n "${DOCKER_TAG:-}" ]; then
            echo "🏷️  Tagging image as: $DOCKER_TAG"
            docker tag "$LOADED_IMAGE" "$DOCKER_TAG"
            
            # Push if requested
            if [ "${DOCKER_PUSH:-}" = "true" ]; then
                echo "📤 Pushing to registry..."
                docker push "$DOCKER_TAG" || {
                    echo "⚠️  Push failed. Make sure you're logged in: docker login"
                }
            fi
        fi
        
        echo "✅ Docker image ready: ${LOADED_IMAGE:-nixos-dev:${PROFILE}}"
    fi
    
    # Copy to output file if specified
    if [ -n "$OUTPUT_FILE" ]; then
        cp "$CONTAINER_PATH" "$OUTPUT_FILE"
        echo "📁 Copied to: $OUTPUT_FILE"
    fi
    
    echo ""
    echo "To load this container in Docker:"
    echo "  gunzip -c $CONTAINER_PATH | docker load"
    echo "  docker run -it nixos-dev:${PROFILE} /bin/bash"
    echo ""
    echo "Or with automatic loading:"
    echo "  LOAD_DOCKER=true $0"
    echo ""
    echo "To tag and push:"
    echo "  LOAD_DOCKER=true DOCKER_TAG=docker.io/user/image:tag DOCKER_PUSH=true $0"
fi