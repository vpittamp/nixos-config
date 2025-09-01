#!/bin/bash
# Build NixOS containers with unified configuration
# Supports both standard containers and devcontainers

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Track timing
BUILD_START_TIME=$(date +%s)
CURRENT_STEP=0
TOTAL_STEPS=0
PROGRESS_PID=""

# Cleanup function
cleanup() {
    local exit_code=$?
    
    # Kill progress indicator if running
    if [ -n "$PROGRESS_PID" ] && kill -0 $PROGRESS_PID 2>/dev/null; then
        kill $PROGRESS_PID 2>/dev/null || true
        echo -ne "\r\033[K"  # Clear the progress line
    fi
    
    # Show error summary if build failed
    if [ $exit_code -ne 0 ]; then
        echo ""
        echo -e "${RED}╔══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║${NC}                   BUILD FAILED                           ${RED}║${NC}"
        echo -e "${RED}╚══════════════════════════════════════════════════════════╝${NC}"
        echo ""
        log_error "Build failed after $(calculate_elapsed $BUILD_START_TIME)"
        
        # Show helpful debugging info
        echo ""
        log_info "Debug information:"
        echo "  • Check build logs: ${CYAN}/tmp/nix-build.log${NC}"
        echo "  • Profile used: ${CYAN}$PROFILE${NC}"
        echo "  • Working directory: ${CYAN}$(pwd)${NC}"
        echo ""
        log_info "Common issues:"
        echo "  • Insufficient disk space"
        echo "  • Network connectivity problems"
        echo "  • Invalid package profile"
        echo "  • Docker daemon not running (if using --load-docker)"
    fi
    
    exit $exit_code
}

# Set up trap for cleanup
trap cleanup EXIT INT TERM

# Parse command line arguments
MODE="container"  # Default mode
PROFILE=""  # Will be set from arguments or default to "essential" later
OUTPUT_FILE=""
PROJECT_DIR=""
VERBOSE=false
DEBUG=false

# Logging functions
log_info() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[${timestamp}]${NC} ${CYAN}ℹ️${NC}  $1"
}

log_success() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[${timestamp}]${NC} ${GREEN}✅${NC} $1"
}

log_warning() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}[${timestamp}]${NC} ${YELLOW}⚠️${NC}  $1"
}

log_error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[${timestamp}]${NC} ${RED}❌${NC} $1"
}

log_step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo ""
    echo -e "${BLUE}[${timestamp}]${NC} ${CYAN}📍 Step ${CURRENT_STEP}/${TOTAL_STEPS}:${NC} $1"
    echo -e "${BLUE}────────────────────────────────────────────────────────${NC}"
}

calculate_elapsed() {
    local start=$1
    local end=$(date +%s)
    local elapsed=$((end - start))
    local hours=$((elapsed / 3600))
    local minutes=$(( (elapsed % 3600) / 60 ))
    local seconds=$((elapsed % 60))
    
    if [ $hours -gt 0 ]; then
        echo "${hours}h ${minutes}m ${seconds}s"
    elif [ $minutes -gt 0 ]; then
        echo "${minutes}m ${seconds}s"
    else
        echo "${seconds}s"
    fi
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
    echo "  --verbose, -v         Enable verbose Nix build output"
    echo "  --debug               Enable debug mode with maximum verbosity"
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
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --debug)
            DEBUG=true
            VERBOSE=true
            shift
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

# Calculate total steps based on configuration
if [ "$MODE" = "devcontainer" ]; then
    TOTAL_STEPS=5
    [ "${LOAD_DOCKER:-}" = "true" ] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    [ -n "${DOCKER_TAG:-}" ] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    [ "${DOCKER_PUSH:-}" = "true" ] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
else
    TOTAL_STEPS=3
    [ "${LOAD_DOCKER:-}" = "true" ] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    [ -n "${DOCKER_TAG:-}" ] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    [ "${DOCKER_PUSH:-}" = "true" ] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    [ -n "$OUTPUT_FILE" ] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
fi

# Print header with configuration summary
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}           🔨 ${GREEN}NixOS Container Builder${NC}                    ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

log_info "Build configuration:"
log_info "  Mode: ${GREEN}${MODE}${NC}"
log_info "  Profile: ${GREEN}${PROFILE}${NC}"
log_info "  Output: ${GREEN}${OUTPUT_FILE:-<none>}${NC}"

# Show enabled features
log_info "Enabled features:"
[ "${CONTAINER_SSH_ENABLED:-}" = "true" ] && log_info "  • SSH server (port ${CONTAINER_SSH_PORT:-2222})"
[ "${VSCODE_TUNNEL_ENABLED:-}" = "true" ] && log_info "  • VS Code tunnel support"
[ "${VSCODE_SERVER_PREINSTALL:-}" = "true" ] && log_info "  • VS Code server pre-installed"
[ "${LOAD_DOCKER:-}" = "true" ] && log_info "  • Auto-load into Docker"
[ -n "${DOCKER_TAG:-}" ] && log_info "  • Docker tag: ${DOCKER_TAG}"
[ "${DOCKER_PUSH:-}" = "true" ] && log_info "  • Push to registry"

# Set environment variables for the build
export NIXOS_CONTAINER=1
export NIXOS_PACKAGES="$PROFILE"

if [ "$MODE" = "devcontainer" ]; then
    log_step "Initializing devcontainer build"
    
    # Set project directory (default to current directory)
    PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
    log_info "Project directory: $PROJECT_DIR"
    
    log_step "Building base NixOS container"
    STEP_START=$(date +%s)
    cd /etc/nixos
    
    # Build Nix command with verbosity options
    NIX_BUILD_CMD="nix build .#container --no-link --print-out-paths"
    
    if [ "$DEBUG" = true ]; then
        NIX_BUILD_CMD="$NIX_BUILD_CMD --debug --show-trace"
        log_info "Debug mode enabled - maximum verbosity"
    elif [ "$VERBOSE" = true ]; then
        NIX_BUILD_CMD="$NIX_BUILD_CMD --verbose --print-build-logs"
        log_info "Verbose mode enabled"
    fi
    
    log_info "Running nix build (this may take several minutes)..."
    
    if [ "$VERBOSE" = true ]; then
        # In verbose mode, show live output
        CONTAINER_PATH=$(eval $NIX_BUILD_CMD 2>&1 | tee /tmp/nix-build.log | while IFS= read -r line; do
            # Parse and format Nix build output
            if [[ "$line" == *"building"* ]]; then
                echo -e "${CYAN}[BUILD]${NC} $line"
            elif [[ "$line" == *"copying"* ]]; then
                echo -e "${BLUE}[COPY]${NC} $line"
            elif [[ "$line" == *"downloading"* ]]; then
                echo -e "${YELLOW}[DOWNLOAD]${NC} $line"
            elif [[ "$line" == *"unpacking"* ]]; then
                echo -e "${YELLOW}[UNPACK]${NC} $line"
            elif [[ "$line" == *"error:"* ]]; then
                echo -e "${RED}[ERROR]${NC} $line"
            elif [[ "$line" == *"warning:"* ]]; then
                echo -e "${YELLOW}[WARNING]${NC} $line"
            elif [[ "$line" == "/nix/store/"* ]]; then
                echo "$line"  # This is likely the final path
            else
                [ "$DEBUG" = true ] && echo -e "${CYAN}[DEBUG]${NC} $line"
            fi
        done | tail -1)
    else
        CONTAINER_PATH=$(eval $NIX_BUILD_CMD 2>&1 | tee /tmp/nix-build.log | tail -1)
    fi
    
    if [ ! -f "$CONTAINER_PATH" ]; then
        log_error "Build failed. Container not found at: $CONTAINER_PATH"
        log_error "Check /tmp/nix-build.log for details"
        exit 1
    fi
    
    log_success "Container built in $(calculate_elapsed $STEP_START)"
    log_info "Container path: $CONTAINER_PATH"
    
    log_step "Loading container into Docker"
    STEP_START=$(date +%s)
    docker load < "$CONTAINER_PATH" | grep "Loaded image" | cut -d' ' -f3 > /tmp/nixos-image-id
    BASE_IMAGE=$(cat /tmp/nixos-image-id)
    
    if [ -z "$BASE_IMAGE" ]; then
        log_error "Failed to load container into Docker"
        exit 1
    fi
    
    log_success "Container loaded in $(calculate_elapsed $STEP_START)"
    log_info "Base image: $BASE_IMAGE"
    
    # Create devcontainer configuration if it doesn't exist
    DEVCONTAINER_DIR="$PROJECT_DIR/.devcontainer"
    TEMP_DEVCONTAINER=false
    
    log_step "Setting up devcontainer configuration"
    STEP_START=$(date +%s)
    
    if [ ! -f "$DEVCONTAINER_DIR/devcontainer.json" ]; then
        log_info "Creating devcontainer configuration..."
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
    
    log_success "Configuration setup completed in $(calculate_elapsed $STEP_START)"
    
    # Build Docker image for devcontainer
    log_step "Building devcontainer Docker image"
    STEP_START=$(date +%s)
    docker tag "$BASE_IMAGE" "nixos-devcontainer:${PROFILE}"
    log_success "Docker image tagged in $(calculate_elapsed $STEP_START)"
    
    # Clean up temporary files if created but keep devcontainer config
    if [ "$TEMP_DEVCONTAINER" = false ]; then
        log_info "Using existing devcontainer configuration"
    else
        log_success "Created devcontainer configuration in $DEVCONTAINER_DIR"
    fi
    
    # Print summary
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}                   BUILD COMPLETE                         ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log_success "Devcontainer ready: nixos-devcontainer:${PROFILE}"
    log_info "Total build time: $(calculate_elapsed $BUILD_START_TIME)"
    echo ""
    log_info "To use this devcontainer:"
    echo "  1. Open VS Code in your project: ${CYAN}code $PROJECT_DIR${NC}"
    echo "  2. Press F1 and run: ${CYAN}'Dev Containers: Reopen in Container'${NC}"
    echo ""
    log_info "Or use Docker directly:"
    echo "  ${CYAN}docker run -it -v $PROJECT_DIR:/workspace nixos-devcontainer:${PROFILE} /bin/bash${NC}"
    
else
    # Build standard container
    log_step "Initializing standard container build"
    cd /etc/nixos
    
    log_step "Building NixOS container"
    STEP_START=$(date +%s)
    log_info "Running nix build with profile: $PROFILE"
    
    # Build Nix command with verbosity options
    NIX_BUILD_CMD="NIXOS_PACKAGES=\"$PROFILE\" nix build .#container --impure --no-link --print-out-paths"
    
    if [ "$DEBUG" = true ]; then
        NIX_BUILD_CMD="$NIX_BUILD_CMD --debug --show-trace"
        log_info "Debug mode enabled - maximum verbosity"
        export NIX_DEBUG=1
    elif [ "$VERBOSE" = true ]; then
        NIX_BUILD_CMD="$NIX_BUILD_CMD --verbose --print-build-logs -L"
        log_info "Verbose mode enabled - showing build logs"
    fi
    
    log_info "This may take several minutes..."
    
    if [ "$VERBOSE" = true ]; then
        # In verbose mode, show live output with formatting
        log_info "Showing live build output:"
        echo ""
        
        # Run build and capture output while showing it
        TEMP_OUTPUT=$(mktemp)
        eval $NIX_BUILD_CMD 2>&1 | tee /tmp/nix-build.log | {
            while IFS= read -r line; do
                # Always show the line for debugging first
                if [[ "$line" == "/nix/store/"* ]] && [[ "$line" == *".tar.gz" ]]; then
                    # This is likely the final path - save it
                    echo "$line" > "$TEMP_OUTPUT"
                    echo -e "${GREEN}[OUTPUT]${NC} $line"
                elif [[ "$line" == *"@nix"* ]]; then
                    # JSON progress from Nix 2.4+
                    if command -v jq &> /dev/null; then
                        formatted=$(echo "$line" | jq -r 'if .action then "[" + .action + "] " + (.path // .drv // .msg // "") else . end' 2>/dev/null)
                        [ -n "$formatted" ] && echo -e "${CYAN}[NIX]${NC} $formatted"
                    fi
                elif [[ "$line" == *"building"* ]] || [[ "$line" == *"Building"* ]]; then
                    echo -e "${CYAN}[BUILD]${NC} $line"
                elif [[ "$line" == *"copying"* ]] || [[ "$line" == *"Copying"* ]]; then
                    echo -e "${BLUE}[COPY]${NC} $line"
                elif [[ "$line" == *"downloading"* ]] || [[ "$line" == *"Downloading"* ]]; then
                    echo -e "${YELLOW}[DOWNLOAD]${NC} $line"
                elif [[ "$line" == *"unpacking"* ]] || [[ "$line" == *"Unpacking"* ]]; then
                    echo -e "${YELLOW}[UNPACK]${NC} $line"
                elif [[ "$line" == *"layer"* ]]; then
                    echo -e "${GREEN}[LAYER]${NC} $line"
                elif [[ "$line" == *"Adding"* ]] && [[ "$line" == *"files"* ]]; then
                    echo -e "${BLUE}[FILES]${NC} $line"
                elif [[ "$line" == *"Packing"* ]]; then
                    echo -e "${CYAN}[PACK]${NC} $line"
                elif [[ "$line" == *"error:"* ]]; then
                    echo -e "${RED}[ERROR]${NC} $line"
                elif [[ "$line" == *"warning:"* ]]; then
                    echo -e "${YELLOW}[WARNING]${NC} $line"
                elif [[ -n "$line" ]]; then
                    # Show all non-empty lines in verbose mode
                    echo -e "${CYAN}[INFO]${NC} $line"
                fi
            done
        }
        BUILD_RESULT=${PIPESTATUS[0]}
        CONTAINER_PATH=$(cat "$TEMP_OUTPUT" 2>/dev/null)
        rm -f "$TEMP_OUTPUT"
    else
        # Non-verbose mode with progress indicator
        (
            COUNT=0
            while true; do
                COUNT=$((COUNT + 1))
                if [ $((COUNT % 12)) -eq 0 ]; then
                    echo -ne "\r${CYAN}[$(date '+%H:%M:%S')]${NC} Still building... ($(calculate_elapsed $STEP_START) elapsed)"
                fi
                sleep 5
            done
        ) &
        PROGRESS_PID=$!
        
        CONTAINER_PATH=$(eval $NIX_BUILD_CMD 2>&1 | tee /tmp/nix-build.log | tail -1)
        BUILD_RESULT=$?
        
        # Stop progress indicator
        kill $PROGRESS_PID 2>/dev/null || true
        echo -ne "\r\033[K"  # Clear the progress line
    fi
    
    # Check if build succeeded
    if [ $BUILD_RESULT -ne 0 ] || [ ! -f "$CONTAINER_PATH" ]; then
        log_error "Build failed. Container path not found: $CONTAINER_PATH"
        log_error "Check /tmp/nix-build.log for details"
        log_info "Last 20 lines of build log:"
        tail -20 /tmp/nix-build.log
        exit 1
    fi
    
    # Get container size
    SIZE=$(du -sh "$CONTAINER_PATH" | cut -f1)
    log_success "Container built in $(calculate_elapsed $STEP_START)"
    log_info "Container path: $CONTAINER_PATH"
    log_info "Container size: $SIZE"
    
    # Option to load into Docker
    if [ "${LOAD_DOCKER:-}" = "true" ] || [ "${AUTO_LOAD:-}" = "true" ]; then
        log_step "Loading container into Docker"
        STEP_START=$(date +%s)
        
        # Handle both .tar.gz and .tar formats and capture the loaded image name
        if [[ "$CONTAINER_PATH" == *.tar.gz ]]; then
            log_info "Decompressing and loading container..."
            LOADED_IMAGE=$(gunzip -c "$CONTAINER_PATH" | docker load 2>&1 | tee /tmp/docker-load.log | grep "Loaded image" | cut -d: -f2- | tr -d ' ')
            if [ -z "$LOADED_IMAGE" ]; then
                log_error "Failed to load container into Docker"
                log_error "Docker output:"
                cat /tmp/docker-load.log
                exit 1
            fi
        else
            LOADED_IMAGE=$(docker load < "$CONTAINER_PATH" 2>&1 | tee /tmp/docker-load.log | grep "Loaded image" | cut -d: -f2- | tr -d ' ')
            if [ -z "$LOADED_IMAGE" ]; then
                log_error "Failed to load container into Docker"
                log_error "Docker output:"
                cat /tmp/docker-load.log
                exit 1
            fi
        fi
        
        log_success "Image loaded in $(calculate_elapsed $STEP_START)"
        log_info "Loaded image: $LOADED_IMAGE"
        
        # Tag the image if requested
        if [ -n "${DOCKER_TAG:-}" ]; then
            log_step "Tagging Docker image"
            STEP_START=$(date +%s)
            docker tag "$LOADED_IMAGE" "$DOCKER_TAG"
            log_success "Image tagged as: $DOCKER_TAG in $(calculate_elapsed $STEP_START)"
            
            # Push if requested
            if [ "${DOCKER_PUSH:-}" = "true" ]; then
                log_step "Pushing to Docker registry"
                STEP_START=$(date +%s)
                if docker push "$DOCKER_TAG"; then
                    log_success "Image pushed to registry in $(calculate_elapsed $STEP_START)"
                else
                    log_warning "Push failed. Make sure you're logged in: docker login"
                fi
            fi
        fi
        
        log_success "Docker image ready: ${LOADED_IMAGE:-nixos-dev:${PROFILE}}"
    fi
    
    # Copy to output file if specified
    if [ -n "$OUTPUT_FILE" ]; then
        log_step "Copying container to output file"
        STEP_START=$(date +%s)
        cp "$CONTAINER_PATH" "$OUTPUT_FILE"
        log_success "Container copied to: $OUTPUT_FILE in $(calculate_elapsed $STEP_START)"
    fi
    
    # Print final summary
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}                   BUILD COMPLETE                         ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    log_success "Build completed successfully!"
    log_info "Total build time: $(calculate_elapsed $BUILD_START_TIME)"
    log_info "Container profile: $PROFILE"
    log_info "Container size: $SIZE"
    
    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    
    if [ -z "${LOAD_DOCKER:-}" ]; then
        echo ""
        log_info "To load this container in Docker:"
        echo "  ${CYAN}gunzip -c $CONTAINER_PATH | docker load${NC}"
        echo "  ${CYAN}docker run -it nixos-dev:${PROFILE} /bin/bash${NC}"
        echo ""
        log_info "Or with automatic loading:"
        echo "  ${CYAN}LOAD_DOCKER=true $0${NC}"
    else
        echo ""
        log_info "Run the container:"
        echo "  ${CYAN}docker run -it ${LOADED_IMAGE:-nixos-dev:${PROFILE}} /bin/bash${NC}"
    fi
    
    if [ -z "${DOCKER_TAG:-}" ]; then
        echo ""
        log_info "To tag and push to registry:"
        echo "  ${CYAN}LOAD_DOCKER=true DOCKER_TAG=docker.io/user/image:tag DOCKER_PUSH=true $0${NC}"
    fi
fi