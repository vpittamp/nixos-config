{ pkgs }:

{
  # Default development shell with container tools
  default = pkgs.mkShell {
    name = "container-dev";
    
    buildInputs = with pkgs; [
      # Container tools
      docker-compose
      dive              # Inspect container layers
      
      # Kubernetes tools
      kubectl
      kubernetes-helm
      k9s               # Terminal UI for Kubernetes
      kind              # Kubernetes in Docker
      
      # Development tools
      git
      jq
      yq
      curl
      
      # Nix tools
      nix-prefetch-docker
      nixpkgs-fmt
    ];
    
    shellHook = ''
      echo "🐳 Container Development Environment"
      echo ""
      echo "Available commands:"
      echo "  docker    - Docker CLI (via Docker Desktop)"
      echo "  docker-compose - Multi-container orchestration"
      echo "  kubectl   - Kubernetes CLI"
      echo "  helm      - Kubernetes package manager"
      echo "  k9s       - Kubernetes TUI"
      echo "  kind      - Kubernetes in Docker"
      echo ""
      echo "Build containers with:"
      echo "  nix build .#basic-container"
      echo "  nix build .#node-app-container"
      echo "  nix build .#python-app-container"
      echo "  nix build .#nixos-full-system"
      echo ""
      echo "Load into Docker with:"
      echo "  docker load < result"
      echo ""
      echo "Docker alias configured: /run/current-system/sw/bin/docker"
    '';
  };
  
  # Kubernetes-focused shell
  k8s = pkgs.mkShell {
    name = "k8s-dev";
    
    buildInputs = with pkgs; [
      kubectl
      kubernetes-helm
      k9s
      kustomize
      kubectx
      stern             # Multi-pod log tailing
      kubeseal          # Sealed secrets
    ];
    
    shellHook = ''
      echo "☸️  Kubernetes Development Environment"
      echo ""
      echo "Kubernetes tools loaded!"
    '';
  };
}