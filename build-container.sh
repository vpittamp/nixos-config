#!/bin/bash
# Build NixOS containers with unified configuration
# Supports both standard containers and devcontainers

set -e

# Parse command line arguments
MODE="container"  # Default mode
PROFILE="essential"
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
    echo "Profiles:"
    echo "  essential              Core tools only (~275MB)"
    echo "  essential,kubernetes   Core + K8s tools (~600MB)"
    echo "  essential,development  Core + dev tools (~600MB)"
    echo "  full                   All packages (~1GB)"
    echo ""
    echo "Examples:"
    echo "  $0 essential output.tar.gz              # Build standard container"
    echo "  $0 --devcontainer full                  # Build devcontainer with full profile"
    echo "  $0 -d -p /my/project development        # Build devcontainer for specific project"
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

# Set first positional argument as profile if provided
if [ -n "${1:-}" ]; then
    PROFILE="$1"
fi
if [ -n "${2:-}" ]; then
    OUTPUT_FILE="$2"
fi

echo "🔨 Building NixOS ${MODE}"
echo "📦 Package profile: $PROFILE"

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
    cd /etc/nixos
    CONTAINER_PATH=$(nix build .#container --no-link --print-out-paths)
    
    # Get container size
    SIZE=$(du -sh "$CONTAINER_PATH" | cut -f1)
    echo "✅ Container built: $CONTAINER_PATH"
    echo "📏 Size: $SIZE"
    
    # Copy to output file if specified
    if [ -n "$OUTPUT_FILE" ]; then
        cp "$CONTAINER_PATH" "$OUTPUT_FILE"
        echo "📁 Copied to: $OUTPUT_FILE"
    fi
    
    echo ""
    echo "To load this container in Docker:"
    echo "  docker load < $CONTAINER_PATH"
    echo "  docker run -it nixos-system:${PROFILE} /bin/bash"
fi