#!/usr/bin/env bash
set -e

# Container NixOS Setup Script with Optimizations
# Usage: bash container-setup.sh [minimal|essential|full]

PROFILE="${1:-essential}"
REPO_URL="https://github.com/vpittamp/nixos-config.git"
NIXOS_DIR="/etc/nixos"

echo "====================================="
echo "NixOS Container Setup"
echo "Profile: $PROFILE"
echo "====================================="

# Function to monitor build progress
monitor_progress() {
    local pid=$1
    local delay=5
    local spinstr='|/-\'
    local temp
    
    echo -n "Building... "
    while kill -0 $pid 2>/dev/null; do
        temp=${spinstr#?}
        printf "[%c]" "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b"
        
        # Check Nix build status
        if [ -f /tmp/nix-build.log ]; then
            local status=$(tail -n1 /tmp/nix-build.log | grep -oE '\[[0-9]+/[0-9]+ built' || echo "")
            if [ -n "$status" ]; then
                printf "\r%-50s" "Building... $status"
            fi
        fi
    done
    printf "\r%-50s\n" "Build complete!"
}

# Step 1: Clone repository if not exists
if [ ! -d "$NIXOS_DIR/.git" ]; then
    echo "Cloning configuration repository..."
    rm -rf "$NIXOS_DIR"
    git clone "$REPO_URL" "$NIXOS_DIR"
    cd "$NIXOS_DIR"
else
    echo "Repository already exists, pulling latest..."
    cd "$NIXOS_DIR"
    git pull
fi

# Step 2: Configure Nix for optimal performance
echo "Configuring Nix for container environment..."
mkdir -p /etc/nix
cat > /etc/nix/nix.conf <<EOF
substituters = https://cache.nixos.org https://nix-community.cachix.org https://devenv.cachix.org
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs= devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=
max-jobs = auto
cores = 0
max-substitution-jobs = 16
connect-timeout = 10
download-attempts = 3
experimental-features = nix-command flakes
EOF

# Restart nix-daemon if running
if systemctl is-active --quiet nix-daemon; then
    systemctl restart nix-daemon
    sleep 2
fi

# Step 3: Pre-fetch critical dependencies
echo "Pre-fetching critical dependencies..."
export NIXOS_PACKAGES="$PROFILE"

# Try minimal build first if not minimal profile
if [ "$PROFILE" != "minimal" ]; then
    echo "Starting with minimal profile for bootstrap..."
    NIXOS_PACKAGES=minimal nix build .#homeConfigurations.vpittamp.activationPackage \
        --no-link \
        --option narinfo-cache-negative-ttl 0 \
        2>&1 | tee /tmp/nix-build-minimal.log &
    
    MINIMAL_PID=$!
    wait $MINIMAL_PID
    MINIMAL_EXIT=$?
    
    if [ $MINIMAL_EXIT -eq 0 ]; then
        echo "Minimal profile built successfully!"
    else
        echo "Warning: Minimal build failed, continuing with selected profile..."
    fi
fi

# Step 4: Build selected profile
echo ""
echo "Building $PROFILE profile..."
echo "This may take several minutes depending on download speed..."
echo ""

# Start the build in background
nix build .#homeConfigurations.vpittamp.activationPackage \
    --print-build-logs \
    --option narinfo-cache-negative-ttl 0 \
    --option keep-going true \
    2>&1 | tee /tmp/nix-build.log &

BUILD_PID=$!

# Monitor progress
monitor_progress $BUILD_PID

# Wait for build to complete
wait $BUILD_PID
BUILD_EXIT=$?

if [ $BUILD_EXIT -ne 0 ]; then
    echo ""
    echo "❌ Build failed! Checking logs..."
    echo ""
    tail -n 20 /tmp/nix-build.log
    echo ""
    echo "Troubleshooting tips:"
    echo "1. Check network connectivity: ping cache.nixos.org"
    echo "2. Check disk space: df -h /"
    echo "3. Try minimal profile: NIXOS_PACKAGES=minimal $0"
    echo "4. Check full logs: cat /tmp/nix-build.log"
    exit 1
fi

# Step 5: Activate configuration
echo ""
echo "Activating Home Manager configuration..."
if [ -L result ]; then
    ./result/activate
    echo "✅ Configuration activated successfully!"
else
    echo "❌ No result symlink found. Build may have failed."
    exit 1
fi

# Step 6: Show summary
echo ""
echo "====================================="
echo "Setup Complete!"
echo "Profile: $PROFILE"
echo ""

# Show installed packages
echo "Installed packages:"
if command -v nix-store >/dev/null 2>&1; then
    nix-store -q --requisites ./result | grep -E '/(bin|sbin)' | head -20
    echo "..."
fi

echo ""
echo "To upgrade to full profile later:"
echo "  NIXOS_PACKAGES=full nix build .#homeConfigurations.vpittamp.activationPackage"
echo "  ./result/activate"
echo ""
echo "====================================="