{ config, pkgs, lib, ... }:

let
  clusterFunctions = ''
    # Cluster management functions
    export STACKS_DIR="''${STACKS_DIR:-$HOME/stacks}"
    
    # Base functions - always non-interactive
    cluster-deploy() {
      local CDK8S_DIR="$STACKS_DIR/cdk8s"
      local REF_DIR="$STACKS_DIR/ref-implementation"
      local ORIG_DIR="$(pwd)"
      
      # Source environment files
      [ -f "$STACKS_DIR/.env-files/wi.env" ] && source "$STACKS_DIR/.env-files/wi.env"
      
      echo "🔨 Synthesizing CDK8s manifests..."
      cd "$CDK8S_DIR" && npm run synth || { cd "$ORIG_DIR"; return 1; }
      
      echo "🚀 Creating cluster with idpbuilder..."
      ${pkgs.idpbuilder}/bin/idpbuilder create \
        -p "$CDK8S_DIR/dist/" \
        -p "$REF_DIR/" \
        --kind-config "$REF_DIR/kind-config-nixos-ssh.yaml" \
        --dev-password "$@"
      
      local result=$?
      cd "$ORIG_DIR"
      return $result
    }
    
    cluster-synth() {
      local CDK8S_DIR="$STACKS_DIR/cdk8s"
      local ORIG_DIR="$(pwd)"
      
      [ -f "$STACKS_DIR/.env-files/wi.env" ] && source "$STACKS_DIR/.env-files/wi.env"
      
      cd "$CDK8S_DIR" && npm run synth
      local result=$?
      [ $result -eq 0 ] && echo "✅ Synthesis complete. Manifests in: $CDK8S_DIR/dist/"
      
      cd "$ORIG_DIR"
      return $result
    }
    
    cluster-recreate() {
      echo "🗑️  Deleting existing cluster..."
      ${pkgs.idpbuilder}/bin/idpbuilder delete || ${pkgs.kind}/bin/kind delete cluster --name localdev
      sleep 3
      cluster-deploy "$@"
    }
    
    cluster-status() {
      echo "📊 Cluster Status:"
      ${pkgs.kubectl}/bin/kubectl cluster-info 2>/dev/null || echo "❌ No cluster found"
      echo ""
      echo "ArgoCD Applications:"
      ${pkgs.kubectl}/bin/kubectl get applications -n argocd 2>/dev/null | head -10 || echo "❌ ArgoCD not available"
    }
    
    # Interactive menu using gum (explicit opt-in)
    cluster-menu() {
      [ ! -t 0 ] && { echo "Interactive mode requires TTY"; return 1; }
      
      local ACTION=$(${pkgs.gum}/bin/gum choose \
        --header "🚀 Cluster Management" \
        "Synthesize Only" \
        "Synthesize & Deploy" \
        "Recreate Cluster" \
        "Show Status" \
        "Exit")
      
      case "$ACTION" in
        "Synthesize Only")
          ${pkgs.gum}/bin/gum spin --spinner dot --title "Synthesizing..." \
            -- bash -c 'cluster-synth'
          ;;
        "Synthesize & Deploy")
          if ${pkgs.gum}/bin/gum confirm "Deploy to cluster?"; then
            ${pkgs.gum}/bin/gum spin --spinner moon --title "Deploying..." \
              -- bash -c 'cluster-deploy'
          fi
          ;;
        "Recreate Cluster")
          ${pkgs.gum}/bin/gum style --foreground 196 "⚠️  WARNING: This will delete the cluster!"
          ${pkgs.gum}/bin/gum confirm "Continue?" && cluster-recreate
          ;;
        "Show Status")
          cluster-status | ${pkgs.gum}/bin/gum pager
          ;;
      esac
    }
    
    # Welcome message when loaded
    if [ -n "$PS1" ]; then
      echo "🎯 Cluster functions loaded: cluster-synth, cluster-deploy, cluster-recreate, cluster-status, cluster-menu"
    fi
  '';
in
{
  programs.bash.initExtra = lib.mkAfter clusterFunctions;
  programs.zsh.initExtra = lib.mkAfter clusterFunctions;
  
  programs.bash.shellAliases = {
    cls = "cluster-synth";
    cld = "cluster-deploy";
    clr = "cluster-recreate";
    clst = "cluster-status";
    clm = "cluster-menu";  # Interactive menu
  };
  
  programs.zsh.shellAliases = config.programs.bash.shellAliases;
  
  home.packages = with pkgs; [ gum ];
  
  home.sessionVariables = {
    STACKS_DIR = "$HOME/stacks";
  };
}