#!/usr/bin/env bash
# Installation guide for restricted containers (like Backstage in Kubernetes)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}     Restricted Container - AI Tools Installation Guide${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${RED}⚠️  Security Restriction Detected${NC}"
echo "This container has security policies that prevent direct Nix installation."
echo ""

echo -e "${GREEN}Option 1: Use a Nix-enabled container image${NC}"
echo "Replace your container image with one that has Nix pre-installed:"
echo ""
echo "  In your Kubernetes deployment/pod spec:"
echo "    image: nixos/nix:latest"
echo "  Or:"
echo "    image: xtruder/nix-devcontainer:latest"
echo ""

echo -e "${GREEN}Option 2: Add a Nix sidecar container${NC}"
echo "Add a sidecar container to your pod with shared volume:"
echo ""
cat << 'EOF'
  containers:
  - name: backstage
    image: backstage:latest
    volumeMounts:
    - name: nix-tools
      mountPath: /opt/nix-tools
      
  - name: nix-sidecar
    image: nixos/nix:latest
    command: ["/bin/sh", "-c"]
    args: 
    - |
      # Install tools
      curl -L https://raw.githubusercontent.com/vpittamp/nixos-config/container-ssh/user/install-container.sh | bash -s essential
      # Copy binaries to shared volume
      cp -r /home/code/.nix-profile/* /opt/nix-tools/
      # Keep container running
      sleep infinity
    volumeMounts:
    - name: nix-tools
      mountPath: /opt/nix-tools
      
  volumes:
  - name: nix-tools
    emptyDir: {}
EOF
echo ""

echo -e "${GREEN}Option 3: Modify security context${NC}"
echo "If you have admin access, modify the pod security context:"
echo ""
cat << 'EOF'
  securityContext:
    allowPrivilegeEscalation: true
    runAsNonRoot: false
    capabilities:
      add:
      - SYS_ADMIN
EOF
echo ""

echo -e "${GREEN}Option 4: Use binary releases directly${NC}"
echo "Download and use the binary releases without Nix:"
echo ""
echo "  # Claude Code"
echo "  npm install -g @anthropic/claude-code"
echo ""
echo "  # Gemini CLI"
echo "  npm install -g @google/gemini-cli"
echo ""
echo "  # Codex"
echo "  npm install -g @openai/codex"
echo ""

echo -e "${GREEN}Option 5: Build a custom container image${NC}"
echo "Create a Dockerfile with Nix and tools pre-installed:"
echo ""
cat << 'EOF'
FROM nixos/nix:latest AS builder
RUN nix-channel --update
RUN curl -L https://raw.githubusercontent.com/vpittamp/nixos-config/container-ssh/user/install-container.sh | bash -s essential

FROM backstage:latest
COPY --from=builder /nix /nix
COPY --from=builder /home/code/.nix-profile /opt/ai-tools
ENV PATH="/opt/ai-tools/bin:${PATH}"
EOF
echo ""

echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}For immediate help, contact your platform administrator to:${NC}"
echo "  • Adjust container security policies"
echo "  • Use a different base image"
echo "  • Enable privilege escalation for installation"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"