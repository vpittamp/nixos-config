#!/usr/bin/env bash

# Quick restart script for interrupted NixOS builds in containers
# This script resumes or restarts a build with optimizations

set -e

cd /etc/nixos

# Check current build status
echo "Checking build status..."

# Export profile (can be overridden)
export NIXOS_PACKAGES="${NIXOS_PACKAGES:-essential}"

echo "Profile: $NIXOS_PACKAGES"
echo ""

# Check if a build is already in progress
if pgrep -f "nix build" > /dev/null; then
    echo "⚠️  A build is already running. Showing progress..."
    echo ""
    
    # Tail the build log
    if [ -f /tmp/nix-build.log ]; then
        tail -f /tmp/nix-build.log
    else
        echo "Waiting for build output..."
        while ! [ -f /tmp/nix-build.log ]; do
            sleep 1
        done
        tail -f /tmp/nix-build.log
    fi
    exit 0
fi

# Apply optimized nix configuration if not already done
if ! grep -q "nix-community.cachix.org" /etc/nix/nix.conf 2>/dev/null; then
    echo "Applying optimized Nix configuration..."
    sudo cp /etc/nixos/scripts/container-nix.conf /etc/nix/nix.conf
    
    # Restart nix-daemon if available
    if systemctl is-active --quiet nix-daemon; then
        sudo systemctl restart nix-daemon
        sleep 2
    fi
fi

# Check if we have a partial build
if [ -L result ]; then
    echo "Found existing build result. Checking if it's current..."
    
    # Check if flake.lock has changed
    if [ result -ot flake.lock ]; then
        echo "Configuration has changed. Rebuilding..."
    else
        echo "Build appears current. Activating..."
        ./result/activate
        echo "✅ Configuration activated!"
        exit 0
    fi
fi

# Start or restart the build
echo "Starting optimized build..."
echo "This will use binary caches for faster downloads."
echo ""

# Run build with progress monitoring
nix build .#homeConfigurations.vpittamp.activationPackage \
    --print-build-logs \
    --option narinfo-cache-negative-ttl 0 \
    --option keep-going true \
    --option connect-timeout 10 \
    --option download-attempts 3 \
    2>&1 | tee /tmp/nix-build.log &

BUILD_PID=$!

# Simple progress indicator
echo -n "Building"
while kill -0 $BUILD_PID 2>/dev/null; do
    echo -n "."
    sleep 2
    
    # Periodically show build status
    if [ -f /tmp/nix-build.log ]; then
        STATUS=$(tail -n1 /tmp/nix-build.log | grep -oE '\[[0-9]+/[0-9]+ built' || echo "")
        if [ -n "$STATUS" ]; then
            printf "\rBuilding... %s     " "$STATUS"
        fi
    fi
done

echo ""

# Check if build succeeded
wait $BUILD_PID
if [ $? -eq 0 ]; then
    echo "✅ Build completed successfully!"
    echo "Activating configuration..."
    ./result/activate
    echo "✅ Configuration activated!"
else
    echo "❌ Build failed. Check /tmp/nix-build.log for details."
    echo ""
    echo "Last 10 lines of log:"
    tail -n 10 /tmp/nix-build.log
    exit 1
fi