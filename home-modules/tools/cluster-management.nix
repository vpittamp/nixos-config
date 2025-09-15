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
      
      # Clear any WSL Docker environment variables
      unset DOCKER_HOST
      unset DOCKER_TLS_VERIFY
      unset DOCKER_CERT_PATH
      
      # Source environment files
      [ -f "$STACKS_DIR/.env-files/wi.env" ] && source "$STACKS_DIR/.env-files/wi.env"
      
      echo "🔨 Synthesizing CDK8s manifests..."
      cd "$CDK8S_DIR" && npm run synth || { cd "$ORIG_DIR"; return 1; }
      
      echo "🚀 Creating cluster with idpbuilder..."
      
      # Check if Linux deployment script exists and use it
      if [ -f "$REF_DIR/deploy-linux-ssh.sh" ]; then
        echo "Using Linux deployment script with direct key mounting and Azure integration..."
        cd "$REF_DIR" && ./deploy-linux-ssh.sh \
          --package "$CDK8S_DIR/dist/" \
          --package "$REF_DIR/" \
          "$@"
      else
        # Fallback to standard idpbuilder with post-setup JWKS sync
        command -v idpbuilder >/dev/null 2>&1 || { echo "❌ idpbuilder not found. Please install it first."; cd "$ORIG_DIR"; return 1; }
        idpbuilder create \
          -p "$CDK8S_DIR/dist/" \
          -p "$REF_DIR/" \
          --kind-config "$REF_DIR/kind-config-nixos-ssh.yaml" \
          --dev-password "$@"
        
        # Sync JWKS after cluster creation
        if [ -f "$REF_DIR/sync-jwks-to-azure.sh" ]; then
          echo "🔄 Syncing JWKS to Azure for External Secrets..."
          cd "$REF_DIR" && ./sync-jwks-to-azure.sh
        fi
      fi
      
      local result=$?
      cd "$ORIG_DIR"
      return $result
    }
    
    cluster-synth() {
      local CDK8S_DIR="$STACKS_DIR/cdk8s"
      local ORIG_DIR="$(pwd)"
      
      # Clear any WSL Docker environment variables
      unset DOCKER_HOST
      unset DOCKER_TLS_VERIFY
      unset DOCKER_CERT_PATH
      
      [ -f "$STACKS_DIR/.env-files/wi.env" ] && source "$STACKS_DIR/.env-files/wi.env"
      
      cd "$CDK8S_DIR" && npm run synth
      local result=$?
      [ $result -eq 0 ] && echo "✅ Synthesis complete. Manifests in: $CDK8S_DIR/dist/"
      
      cd "$ORIG_DIR"
      return $result
    }
    
    cluster-recreate() {
      # Clear any WSL Docker environment variables
      unset DOCKER_HOST
      unset DOCKER_TLS_VERIFY
      unset DOCKER_CERT_PATH
      
      echo "🗑️  Deleting existing cluster..."
      idpbuilder delete || kind delete cluster --name localdev
      sleep 3
      cluster-deploy "$@"
    }
    
    cluster-status() {
      echo "📊 Cluster Status:"
      kubectl cluster-info 2>/dev/null || echo "❌ No cluster found"
      echo ""
      echo "ArgoCD Applications:"
      kubectl get applications -n argocd 2>/dev/null | head -10 || echo "❌ ArgoCD not available"
    }
    
    # Interactive menu using gum (explicit opt-in)
    cluster-menu() {
      [ ! -t 0 ] && { echo "Interactive mode requires TTY"; return 1; }
      
      # Clear any WSL Docker environment variables at menu start
      unset DOCKER_HOST
      unset DOCKER_TLS_VERIFY
      unset DOCKER_CERT_PATH
      
      # Option to show logs by default
      local SHOW_LOGS=''${CLUSTER_MENU_LOGS:-true}
      
      local ACTION=$(${pkgs.gum}/bin/gum choose \
        --header "🚀 Cluster Management" \
        "Synthesize Only" \
        "Synthesize & Deploy (spinner)" \
        "Synthesize & Deploy (with logs)" \
        "Recreate Cluster" \
        "Show Status" \
        "Toggle Log Mode (current: $SHOW_LOGS)" \
        "Exit")
      
      case "$ACTION" in
        "Synthesize Only")
          echo "🔨 Running synthesis..."
          cluster-synth
          ;;
        "Synthesize & Deploy (spinner)")
          if ${pkgs.gum}/bin/gum confirm "Deploy to cluster?"; then
            echo "🚀 Starting deployment..."
            # Show spinner with periodic status updates
            (cluster-deploy 2>&1 | tee /tmp/cluster-deploy.log) &
            local PID=$!
            ${pkgs.gum}/bin/gum spin --spinner moon --title "Deploying... (logs in /tmp/cluster-deploy.log)" \
              -- bash -c "while kill -0 $PID 2>/dev/null; do sleep 1; done"
            wait $PID
            local RESULT=$?
            if [ $RESULT -eq 0 ]; then
              ${pkgs.gum}/bin/gum style --foreground 82 "✅ Deployment successful!"
            else
              ${pkgs.gum}/bin/gum style --foreground 196 "❌ Deployment failed! Check /tmp/cluster-deploy.log"
            fi
          fi
          ;;
        "Synthesize & Deploy (with logs)")
          if ${pkgs.gum}/bin/gum confirm "Deploy to cluster with visible logs?"; then
            echo "📋 Running with full output..."
            cluster-deploy
            echo ""
            ${pkgs.gum}/bin/gum style --foreground 82 "Press Enter to continue..."
            read -r
          fi
          ;;
        "Recreate Cluster")
          ${pkgs.gum}/bin/gum style --foreground 196 "⚠️  WARNING: This will delete the cluster!"
          if ${pkgs.gum}/bin/gum confirm "Continue?"; then
            echo "🗑️  Recreating cluster..."
            cluster-recreate
          fi
          ;;
        "Show Status")
          cluster-status | ${pkgs.gum}/bin/gum pager
          ;;
        "Toggle Log Mode"*)
          if [ "$SHOW_LOGS" = "true" ]; then
            export CLUSTER_MENU_LOGS=false
            echo "Log mode disabled - will use spinners"
          else
            export CLUSTER_MENU_LOGS=true
            echo "Log mode enabled - will show full output"
          fi
          sleep 1
          cluster-menu  # Re-run menu
          ;;
      esac
    }
    
    # Welcome message disabled - functions are available without announcement
    # if [ -n "$PS1" ]; then
    #   echo "🎯 Cluster functions loaded: cluster-synth, cluster-deploy, cluster-recreate, cluster-status, cluster-menu"
    # fi
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