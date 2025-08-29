#!/bin/bash
# Build NixOS containers with unified configuration
# Supports both standard containers and devcontainers

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Timing variables
declare -A STEP_TIMES
declare -A STEP_NAMES
STEP_COUNT=0
BUILD_START_TIME=""

# Package size tracking variables
declare -A PACKAGE_SIZES
declare -A PACKAGE_CLOSURE_SIZES
PACKAGE_SIZE_FILE="/tmp/nix-package-sizes-$$.json"
SHOW_PACKAGE_SIZES="${SHOW_PACKAGE_SIZES:-true}"
SIZE_ANALYSIS_VERBOSE="${SIZE_ANALYSIS_VERBOSE:-false}"

# Parse command line arguments
MODE="container"  # Default mode
PROFILE=""  # Will be set from arguments or default to "essential" later
OUTPUT_FILE=""
PROJECT_DIR=""

# Docker Hub defaults
DOCKER_USER="${DOCKER_USER:-vpittamp23}"
DEFAULT_VERSION="v1.23.0"  # Starting version

# Function to get next version number
get_next_version() {
    local profile="$1"
    local base_version="${VERSION:-}"
    
    if [ -n "$base_version" ]; then
        echo "$base_version"
        return
    fi
    
    # Check existing tags in Docker Hub
    local latest_tag=$(docker images "${DOCKER_USER}/nixos-dev" --format "{{.Tag}}" 2>/dev/null | \
                       grep -E "^v[0-9]+\.[0-9]+\.[0-9]+-${profile}$" | \
                       sort -V | tail -1)
    
    if [ -z "$latest_tag" ]; then
        echo "${DEFAULT_VERSION}-${profile}"
    else
        # Extract version and increment patch number
        local version_part=$(echo "$latest_tag" | sed "s/-${profile}$//" | sed 's/^v//')
        local major=$(echo "$version_part" | cut -d. -f1)
        local minor=$(echo "$version_part" | cut -d. -f2)
        local patch=$(echo "$version_part" | cut -d. -f3)
        patch=$((patch + 1))
        echo "v${major}.${minor}.${patch}-${profile}"
    fi
}

# Function to format duration from seconds
format_duration() {
    local duration=$1
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    if [ $minutes -gt 0 ]; then
        printf "%dm %ds" $minutes $seconds
    else
        printf "%ds" $seconds
    fi
}

# Function to record step timing
start_step() {
    local step_name="$1"
    STEP_COUNT=$((STEP_COUNT + 1))
    STEP_NAMES[$STEP_COUNT]="$step_name"
    STEP_TIMES["${STEP_COUNT}_start"]=$(date +%s)
    echo -e "${CYAN}⏱️  [$(date +%H:%M:%S)] Starting: $step_name${NC}"
}

# Function to end step timing
end_step() {
    local end_time=$(date +%s)
    local start_time=${STEP_TIMES["${STEP_COUNT}_start"]}
    local duration=$((end_time - start_time))
    STEP_TIMES["${STEP_COUNT}_duration"]=$duration
    echo -e "${GREEN}✓ [$(date +%H:%M:%S)] Completed: ${STEP_NAMES[$STEP_COUNT]} ($(format_duration $duration))${NC}"
}

# Function to print timing summary
print_timing_summary() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}                   Build Time Summary                  ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    
    local total_duration=0
    for i in $(seq 1 $STEP_COUNT); do
        local duration=${STEP_TIMES["${i}_duration"]}
        if [ -n "$duration" ]; then
            total_duration=$((total_duration + duration))
            printf "  %-40s %10s\n" "${STEP_NAMES[$i]}" "$(format_duration $duration)"
        fi
    done
    
    echo -e "${BLUE}───────────────────────────────────────────────────────${NC}"
    printf "  ${GREEN}%-40s %10s${NC}\n" "Total Build Time" "$(format_duration $total_duration)"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
}

# Function to get packages list based on profile
get_profile_packages() {
    local profile="$1"
    local packages=""
    
    # Base minimal packages
    packages="tmux git vim fzf ripgrep fd bat curl wget jq which file"
    
    # Add essential packages if profile includes them
    if [[ "$profile" == *"essential"* ]] || [[ "$profile" == "full" ]]; then
        packages="$packages gnugrep eza zoxide yq tree htop ncurses direnv stow gum"
        packages="$packages gnutar gzip gnused glibc coreutils findutils nodejs_20 nix tailscale"
        packages="$packages sesh claude-manager vscode-cli azure-cli-bin"
    fi
    
    # Add kubernetes packages if requested
    if [[ "$profile" == *"kubernetes"* ]] || [[ "$profile" == "full" ]]; then
        packages="$packages kubectl helm k9s kubectx kubernetes-helm devspace"
    fi
    
    # Add development packages if requested
    if [[ "$profile" == *"development"* ]] || [[ "$profile" == "full" ]]; then
        packages="$packages go rustc gcc python3 deno"
    fi
    
    echo "$packages"
}

# Function to collect package sizes asynchronously
collect_package_sizes() {
    local profile="$1"
    local output_file="$2"
    
    if [ "$SHOW_PACKAGE_SIZES" != "true" ]; then
        return
    fi
    
    echo -e "${CYAN}📊 Analyzing package sizes in background...${NC}"
    
    # Get package list
    local packages=$(get_profile_packages "$profile")
    
    # Start background process to collect sizes
    (
        echo "{" > "$output_file.tmp"
        echo '  "packages": {' >> "$output_file.tmp"
        
        local first=true
        for pkg in $packages; do
            # Skip certain pseudo-packages
            [[ "$pkg" == "claude-manager" ]] && continue
            [[ "$pkg" == "vscode-cli" ]] && continue
            [[ "$pkg" == "azure-cli-bin" ]] && continue
            [[ "$pkg" == "sesh" ]] && continue
            
            if [ "$first" = false ]; then
                echo "," >> "$output_file.tmp"
            fi
            first=false
            
            # Get package size (timeout after 2 seconds per package)
            local size_info=$(timeout 2 nix path-info --closure-size --json "nixpkgs#$pkg" 2>/dev/null || echo "{}")
            if [ -n "$size_info" ] && [ "$size_info" != "{}" ]; then
                local closure_size=$(echo "$size_info" | jq -r '.[].closureSize // 0' 2>/dev/null || echo 0)
                local size_mb=$(echo "scale=2; $closure_size / 1048576" | bc 2>/dev/null || echo 0)
                echo -n "    \"$pkg\": {\"closureSize\": $closure_size, \"sizeMB\": $size_mb}" >> "$output_file.tmp"
            else
                echo -n "    \"$pkg\": {\"closureSize\": 0, \"sizeMB\": 0}" >> "$output_file.tmp"
            fi
        done
        
        echo "" >> "$output_file.tmp"
        echo '  }' >> "$output_file.tmp"
        echo '}' >> "$output_file.tmp"
        
        mv "$output_file.tmp" "$output_file"
    ) &
    
    PACKAGE_SIZE_PID=$!
}

# Function to print package size summary
print_package_size_summary() {
    if [ "$SHOW_PACKAGE_SIZES" != "true" ]; then
        return
    fi
    
    # Wait for background process if still running (max 5 seconds)
    if [ -n "$PACKAGE_SIZE_PID" ]; then
        local wait_count=0
        while kill -0 $PACKAGE_SIZE_PID 2>/dev/null && [ $wait_count -lt 10 ]; do
            sleep 0.5
            wait_count=$((wait_count + 1))
        done
    fi
    
    if [ ! -f "$PACKAGE_SIZE_FILE" ]; then
        echo -e "${YELLOW}⚠️  Package size analysis not available${NC}"
        return
    fi
    
    echo ""
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}                 📦 Package Size Analysis              ${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════${NC}"
    
    # Parse and sort packages by size
    local total_size=0
    local package_data=$(cat "$PACKAGE_SIZE_FILE" | jq -r '.packages | to_entries | sort_by(-.value.closureSize) | .[]' 2>/dev/null)
    
    if [ -z "$package_data" ]; then
        echo "  No package data available"
        return
    fi
    
    # Calculate total size first
    total_size=$(cat "$PACKAGE_SIZE_FILE" | jq '[.packages[].closureSize] | add' 2>/dev/null || echo 0)
    
    # Print header
    printf "  %-25s %12s %10s\n" "Package" "Size" "% of Total"
    echo -e "${MAGENTA}───────────────────────────────────────────────────────${NC}"
    
    # Print packages
    local count=0
    echo "$package_data" | while IFS= read -r line; do
        local pkg_name=$(echo "$line" | jq -r '.key')
        local pkg_size=$(echo "$line" | jq -r '.value.closureSize')
        local pkg_size_mb=$(echo "$line" | jq -r '.value.sizeMB')
        
        if [ "$pkg_size" -gt 0 ] && [ "$total_size" -gt 0 ]; then
            local percentage=$(echo "scale=1; $pkg_size * 100 / $total_size" | bc)
            
            # Show top 10 by default, or all if verbose
            if [ "$SIZE_ANALYSIS_VERBOSE" = "true" ] || [ $count -lt 10 ]; then
                printf "  %-25s %10s MB %9s%%\n" "$pkg_name" "$pkg_size_mb" "$percentage"
            fi
            count=$((count + 1))
        fi
    done
    
    if [ "$SIZE_ANALYSIS_VERBOSE" != "true" ] && [ $count -gt 10 ]; then
        echo "  ... ($(($count - 10)) more packages, use SIZE_ANALYSIS_VERBOSE=true to see all)"
    fi
    
    # Print total
    echo -e "${MAGENTA}───────────────────────────────────────────────────────${NC}"
    local total_mb=$(echo "scale=2; $total_size / 1048576" | bc 2>/dev/null || echo 0)
    printf "  ${GREEN}%-25s %10s MB %9s%%${NC}\n" "Total (Closure Size)" "$total_mb" "100.0"
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════${NC}"
    
    # Clean up temp file
    rm -f "$PACKAGE_SIZE_FILE" "$PACKAGE_SIZE_FILE.tmp" 2>/dev/null
}

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
    echo "  SHOW_PACKAGE_SIZES=true  Analyze and display package sizes (adds ~30s)"
    echo "  DOCKER_PUSH=true       Push the tagged image to registry"
    echo "  DOCKER_USER=<user>     Docker Hub username (default: vpittamp23)"
    echo "  VERSION=<version>      Version tag (default: auto-incremented from v1.23.0)"
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
    BUILD_START_TIME=$(date +%s)
    echo "🐳 Building devcontainer..."
    
    # Set project directory (default to current directory)
    PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
    echo "📁 Project directory: $PROJECT_DIR"
    
    # First build the base NixOS container
    start_step "Building base NixOS container"
    cd /etc/nixos
    CONTAINER_PATH=$(nix build .#container --no-link --print-out-paths)
    end_step
    
    # Load the container into Docker
    start_step "Loading container into Docker"
    docker load < "$CONTAINER_PATH" | grep "Loaded image" | cut -d' ' -f3 > /tmp/nixos-image-id
    BASE_IMAGE=$(cat /tmp/nixos-image-id)
    end_step
    
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
    start_step "Tagging devcontainer Docker image"
    docker tag "$BASE_IMAGE" "nixos-devcontainer:${PROFILE}"
    end_step
    
    # Clean up temporary files if created but keep devcontainer config
    if [ "$TEMP_DEVCONTAINER" = false ]; then
        echo "ℹ️  Using existing devcontainer configuration"
    else
        echo "✅ Created devcontainer configuration in $DEVCONTAINER_DIR"
    fi
    
    # Print timing summary
    print_timing_summary
    
    echo ""
    echo -e "${GREEN}✅ Devcontainer ready: nixos-devcontainer:${PROFILE}${NC}"
    echo ""
    echo "To use this devcontainer:"
    echo "  1. Open VS Code in your project: code $PROJECT_DIR"
    echo "  2. Press F1 and run: 'Dev Containers: Reopen in Container'"
    echo ""
    echo "Or use Docker directly:"
    echo "  docker run -it -v $PROJECT_DIR:/workspace nixos-devcontainer:${PROFILE} /bin/bash"
    
else
    # Build standard container
    BUILD_START_TIME=$(date +%s)
    
    # Start collecting package sizes in the background if enabled
    if [ "$SHOW_PACKAGE_SIZES" = "true" ]; then
        PACKAGE_SIZE_FILE="/tmp/package_sizes_$$_$(date +%s).json"
        collect_package_sizes "$PROFILE" "$PACKAGE_SIZE_FILE"
    fi
    
    start_step "Nix container build"
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
        echo -e "${RED}❌ Build failed. Container path not found: $CONTAINER_PATH${NC}"
        exit 1
    fi
    
    end_step
    
    # Get container size
    start_step "Calculating container size"
    SIZE=$(du -sh "$CONTAINER_PATH" | cut -f1)
    echo "✅ Container built: $CONTAINER_PATH"
    echo "📏 Size: $SIZE"
    end_step
    
    # Option to load into Docker
    if [ "${LOAD_DOCKER:-}" = "true" ] || [ "${AUTO_LOAD:-}" = "true" ]; then
        start_step "Loading container into Docker"
        
        # Handle both .tar.gz and .tar formats and capture the loaded image name
        if [[ "$CONTAINER_PATH" == *.tar.gz ]]; then
            echo "🔓 Decompressing and loading..."
            LOADED_IMAGE=$(gunzip -c "$CONTAINER_PATH" | docker load 2>&1 | grep "Loaded image" | cut -d: -f2- | tr -d ' ')
            if [ -z "$LOADED_IMAGE" ]; then
                echo -e "${RED}❌ Failed to load container into Docker${NC}"
                exit 1
            fi
        else
            LOADED_IMAGE=$(docker load < "$CONTAINER_PATH" 2>&1 | grep "Loaded image" | cut -d: -f2- | tr -d ' ')
            if [ -z "$LOADED_IMAGE" ]; then
                echo -e "${RED}❌ Failed to load container into Docker${NC}"
                exit 1
            fi
        fi
        
        echo "📦 Loaded image: $LOADED_IMAGE"
        end_step
        
        # Auto-generate tag if pushing without explicit tag
        if [ "${DOCKER_PUSH:-}" = "true" ] && [ -z "${DOCKER_TAG:-}" ]; then
            NEXT_VERSION=$(get_next_version "$PROFILE")
            DOCKER_TAG="docker.io/${DOCKER_USER}/nixos-dev:${NEXT_VERSION}"
            echo "📋 Auto-generated tag: $DOCKER_TAG"
        fi
        
        # Tag the image if requested or auto-generated
        if [ -n "${DOCKER_TAG:-}" ]; then
            start_step "Tagging Docker image"
            docker tag "$LOADED_IMAGE" "$DOCKER_TAG"
            echo "🏷️  Tagged as: $DOCKER_TAG"
            end_step
            
            # Push if requested
            if [ "${DOCKER_PUSH:-}" = "true" ]; then
                start_step "Pushing to Docker registry"
                if docker push "$DOCKER_TAG"; then
                    echo "📤 Successfully pushed to registry"
                    echo -e "${GREEN}✅ Image available at: $DOCKER_TAG${NC}"
                else
                    echo -e "${YELLOW}⚠️  Push failed. Make sure you're logged in: docker login${NC}"
                fi
                end_step
            fi
        fi
        
        echo -e "${GREEN}✅ Docker image ready: ${LOADED_IMAGE:-nixos-dev:${PROFILE}}${NC}"
    fi
    
    # Copy to output file if specified
    if [ -n "$OUTPUT_FILE" ]; then
        start_step "Copying to output file"
        cp "$CONTAINER_PATH" "$OUTPUT_FILE"
        echo "📁 Copied to: $OUTPUT_FILE"
        end_step
    fi
    
    # Print timing summary
    print_timing_summary
    
    # Print package size summary if available
    if [ -n "$PACKAGE_SIZE_FILE" ] && [ -f "$PACKAGE_SIZE_FILE" ]; then
        print_package_size_summary "$PACKAGE_SIZE_FILE"
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
    echo ""
    echo "Or auto-tag and push to Docker Hub (vpittamp23):"
    echo "  LOAD_DOCKER=true DOCKER_PUSH=true $0"
fi

# Add trap to ensure timing summary is printed on exit
trap 'if [ $STEP_COUNT -gt 0 ] && [ -z "$SUMMARY_PRINTED" ]; then print_timing_summary; fi' EXIT