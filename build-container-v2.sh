#!/usr/bin/env bash
# Improved container build script with proper profile support and layering

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
PROFILE="${1:-essential}"
VERSION="${2:-v2.25}"
REGISTRY="${DOCKER_REGISTRY:-docker.io}"
REPO="${DOCKER_REPO:-vpittamp23/nixos-dev}"
PUSH="${DOCKER_PUSH:-false}"
LOAD="${DOCKER_LOAD:-true}"

# Display configuration
echo -e "${BLUE}=== NixOS Container Build Script v2 ===${NC}"
echo -e "${GREEN}Configuration:${NC}"
echo "  Profile: $PROFILE"
echo "  Version: $VERSION"
echo "  Registry: $REGISTRY"
echo "  Repository: $REPO"
echo "  Push to registry: $PUSH"
echo "  Load to Docker: $LOAD"
echo ""

# Check if we're in the right directory
if [ ! -f "flake.nix" ]; then
    echo -e "${RED}Error: flake.nix not found. Run this script from /etc/nixos${NC}"
    exit 1
fi

# Function to build container with specific profile
build_container() {
    local profile=$1
    local build_start=$(date +%s)
    
    echo -e "${BLUE}Building container with profile: $profile${NC}"
    
    # Set environment variable for the build
    export NIXOS_PACKAGES="$profile"
    
    # Build the container
    echo "Running: nix build .#container --impure"
    if nix build .#container --impure; then
        local build_end=$(date +%s)
        local build_time=$((build_end - build_start))
        echo -e "${GREEN}✓ Container built successfully in ${build_time}s${NC}"
        
        # Get the size
        local size=$(du -sh result | cut -f1)
        echo -e "${GREEN}  Size: $size${NC}"
        
        return 0
    else
        echo -e "${RED}✗ Build failed${NC}"
        return 1
    fi
}

# Function to load container into Docker
load_container() {
    local tag=$1
    echo -e "${BLUE}Loading container into Docker...${NC}"
    
    if docker load < result; then
        # Tag the image properly
        docker tag nixos-dev:latest "$REGISTRY/$REPO:$tag"
        docker tag nixos-dev:latest "$REGISTRY/$REPO:$PROFILE"
        
        echo -e "${GREEN}✓ Container loaded and tagged${NC}"
        echo "  Tags:"
        echo "    - $REGISTRY/$REPO:$tag"
        echo "    - $REGISTRY/$REPO:$PROFILE"
        return 0
    else
        echo -e "${RED}✗ Failed to load container${NC}"
        return 1
    fi
}

# Function to push container to registry
push_container() {
    local tag=$1
    echo -e "${BLUE}Pushing container to registry...${NC}"
    
    if docker push "$REGISTRY/$REPO:$tag"; then
        echo -e "${GREEN}✓ Pushed $REGISTRY/$REPO:$tag${NC}"
    else
        echo -e "${YELLOW}⚠ Failed to push $REGISTRY/$REPO:$tag${NC}"
    fi
    
    if docker push "$REGISTRY/$REPO:$PROFILE"; then
        echo -e "${GREEN}✓ Pushed $REGISTRY/$REPO:$PROFILE${NC}"
    else
        echo -e "${YELLOW}⚠ Failed to push $REGISTRY/$REPO:$PROFILE${NC}"
    fi
}

# Function to test container
test_container() {
    local tag=$1
    echo -e "${BLUE}Testing container functionality...${NC}"
    
    # Test 1: Basic container run
    echo -n "  Testing basic run... "
    if docker run --rm "$REGISTRY/$REPO:$tag" echo "Hello from container" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
    
    # Test 2: Nix shell functionality
    echo -n "  Testing nix shell... "
    if docker run --rm "$REGISTRY/$REPO:$tag" bash -c "IN_NIX_SHELL=1 nix shell nixpkgs#hello --impure --command hello" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
    
    # Test 3: Flake directory
    echo -n "  Testing flake directory... "
    if docker run --rm "$REGISTRY/$REPO:$tag" test -d /opt/nix-flakes; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
    
    # Test 4: Helper scripts
    echo -n "  Testing helper scripts... "
    if docker run --rm "$REGISTRY/$REPO:$tag" bash -c "source /etc/profile.d/flake-helpers.sh && type nix-dev" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
    
    echo -e "${GREEN}All tests passed!${NC}"
    return 0
}

# Main execution
main() {
    local start_time=$(date +%s)
    
    # Step 1: Build
    if ! build_container "$PROFILE"; then
        echo -e "${RED}Build failed, exiting${NC}"
        exit 1
    fi
    
    # Step 2: Load (if enabled)
    if [ "$LOAD" = "true" ]; then
        if ! load_container "$VERSION"; then
            echo -e "${RED}Load failed, exiting${NC}"
            exit 1
        fi
        
        # Step 3: Test
        if ! test_container "$VERSION"; then
            echo -e "${YELLOW}⚠ Some tests failed${NC}"
        fi
        
        # Step 4: Push (if enabled)
        if [ "$PUSH" = "true" ]; then
            push_container "$VERSION"
        fi
    fi
    
    local end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    
    echo ""
    echo -e "${GREEN}=== Build Complete ===${NC}"
    echo "  Total time: ${total_time}s"
    echo "  Profile: $PROFILE"
    echo "  Version: $VERSION"
    echo ""
    echo "To run the container:"
    echo -e "${BLUE}  docker run -it $REGISTRY/$REPO:$VERSION /bin/bash${NC}"
    echo ""
    echo "To use in Kubernetes:"
    echo -e "${BLUE}  kubectl set image deployment/backstage backstage=$REGISTRY/$REPO:$VERSION${NC}"
}

# Run main function
main "$@"