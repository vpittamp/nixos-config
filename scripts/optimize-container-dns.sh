#!/usr/bin/env bash
# Optimize DNS and network settings in the container

set -e

echo "Optimizing container network settings..."

# 1. Create optimized resolv.conf with Google DNS as fallback
cat > /tmp/resolv.conf.optimized << 'EOF'
# Cluster DNS (keep first for service resolution)
search backstage.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.161.115

# Add public DNS as fallback for external resolution
nameserver 8.8.8.8
nameserver 1.1.1.1

# Optimize DNS query behavior
options ndots:2 timeout:2 attempts:2
EOF

# 2. Apply if different from current
if ! diff -q /etc/resolv.conf /tmp/resolv.conf.optimized > /dev/null 2>&1; then
    echo "Updating DNS configuration..."
    cp /tmp/resolv.conf.optimized /etc/resolv.conf
fi

# 3. Create optimized Nix configuration with connection tuning
mkdir -p ~/.config/nix
cat > ~/.config/nix/nix.conf << 'EOF'
# Binary caches
substituters = https://cache.nixos.org https://nix-community.cachix.org
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=

# Network optimizations for container environment
connect-timeout = 5
download-attempts = 5
http-connections = 128
max-substitution-jobs = 32

# Use parallel downloads
max-jobs = auto
cores = 0

# Enable features
experimental-features = nix-command flakes

# Fallback to building if download is too slow
fallback = true
EOF

# 4. Set environment variables for better network performance
export NIX_CURL_FLAGS="--retry 5 --retry-delay 1 --retry-max-time 40 --connect-timeout 5"

# 5. Test DNS resolution
echo ""
echo "Testing DNS resolution..."
if command -v nslookup > /dev/null 2>&1; then
    nslookup cache.nixos.org || echo "Warning: DNS resolution test failed"
else
    echo "nslookup not available, skipping DNS test"
fi

# 6. Create a wrapper script for Nix builds with optimizations
cat > ~/nix-build-optimized.sh << 'EOF'
#!/usr/bin/env bash
# Optimized Nix build wrapper for container environment

export NIX_CURL_FLAGS="--retry 5 --retry-delay 1 --retry-max-time 40 --connect-timeout 5"

echo "Running optimized Nix build..."
echo "Using substituters: cache.nixos.org, nix-community.cachix.org"
echo ""

# Run with optimized settings
exec nix build "$@" \
    --option connect-timeout 5 \
    --option download-attempts 5 \
    --option http-connections 128 \
    --option max-substitution-jobs 32 \
    --option narinfo-cache-negative-ttl 0 \
    --print-build-logs
EOF

chmod +x ~/nix-build-optimized.sh

echo ""
echo "✅ Container network optimizations applied!"
echo ""
echo "To build with optimizations, use:"
echo "  NIXOS_PACKAGES=minimal ~/nix-build-optimized.sh .#homeConfigurations.vpittamp.activationPackage"
echo ""
echo "Note: If downloads are still slow, run the PowerShell script on Windows host:"
echo "  /etc/nixos/scripts/fix-wsl2-network.ps1"