{ config, pkgs, lib, ... }:

let
  clusterFunctions = ''
    # Cluster management functions
    export STACKS_DIR="''${STACKS_DIR:-$HOME/stacks}"
    
    # Azure authentication helper functions
    check-azure-auth() {
      # Check if logged in and token is valid
      local token_expiry=$(az account get-access-token --query "expiresOn" -o tsv 2>/dev/null || echo "")
      
      if [ -z "$token_expiry" ]; then
        # Not logged in
        ${pkgs.gum}/bin/gum style --foreground 214 "🔐 Azure authentication required"
        if ${pkgs.gum}/bin/gum confirm "Log in to Azure now?"; then
          ${pkgs.gum}/bin/gum style --foreground 45 "Opening Azure login..."
          echo ""
          echo "Please complete the authentication in your browser"
          echo ""
          az login
          if [ $? -eq 0 ]; then
            local account=$(az account show --query "user.name" -o tsv 2>/dev/null)
            ${pkgs.gum}/bin/gum style --foreground 82 "✅ Successfully logged in as: $account"
            return 0
          else
            ${pkgs.gum}/bin/gum style --foreground 196 "❌ Azure login failed"
            return 1
          fi
        else
          ${pkgs.gum}/bin/gum style --foreground 196 "❌ Azure login required for this operation"
          return 1
        fi
      else
        # Check if token is expired or about to expire (within 5 minutes)
        local current_time=$(date +%s)
        local expiry_time=$(date -d "$token_expiry" +%s 2>/dev/null || echo 0)
        local time_diff=$((expiry_time - current_time))
        
        if [ $time_diff -lt 300 ]; then
          ${pkgs.gum}/bin/gum style --foreground 214 "⚠️  Azure token expired or expiring soon (expires: $token_expiry)"
          if ${pkgs.gum}/bin/gum confirm "Refresh Azure login?"; then
            ${pkgs.gum}/bin/gum style --foreground 45 "Refreshing Azure login..."
            az login
            if [ $? -eq 0 ]; then
              local account=$(az account show --query "user.name" -o tsv 2>/dev/null)
              ${pkgs.gum}/bin/gum style --foreground 82 "✅ Successfully refreshed login as: $account"
              return 0
            else
              ${pkgs.gum}/bin/gum style --foreground 196 "❌ Azure login refresh failed"
              return 1
            fi
          else
            ${pkgs.gum}/bin/gum style --foreground 196 "❌ Azure token may expire during operation"
            return 1
          fi
        else
          # Token is valid
          local account=$(az account show --query "user.name" -o tsv 2>/dev/null)
          local subscription=$(az account show --query "name" -o tsv 2>/dev/null)
          ${pkgs.gum}/bin/gum style --foreground 82 "✅ Azure authenticated"
          echo "   Account: $account"
          echo "   Subscription: $subscription"
          echo "   Token valid until: $token_expiry"
        fi
      fi
      return 0
    }
    
    # Get Azure status for display
    get-azure-status() {
      if ! command -v az &>/dev/null; then
        echo "Azure CLI not installed"
        return
      fi
      
      local account=$(az account show --query "user.name" -o tsv 2>/dev/null || echo "")
      if [ -z "$account" ]; then
        echo "Not logged in"
      else
        # Check token expiry
        local token_expiry=$(az account get-access-token --query "expiresOn" -o tsv 2>/dev/null || echo "")
        if [ -n "$token_expiry" ]; then
          local current_time=$(date +%s)
          local expiry_time=$(date -d "$token_expiry" +%s 2>/dev/null || echo 0)
          local time_diff=$((expiry_time - current_time))
          
          if [ $time_diff -lt 300 ]; then
            echo "$account (⚠️ expiring)"
          else
            echo "$account"
          fi
        else
          echo "$account"
        fi
      fi
    }
    
    # Base functions - always non-interactive
    cluster-deploy() {
      # Check if being called internally (skip auth check if SKIP_AZURE_CHECK is set)
      if [ "''${SKIP_AZURE_CHECK:-}" != "true" ]; then
        echo "🔐 Checking Azure authentication..."
        check-azure-auth || return 1
        echo ""
      fi
      
      local CDK8S_DIR="$STACKS_DIR/cdk8s"
      local REF_DIR="$STACKS_DIR/ref-implementation"
      local ORIG_DIR="$(pwd)"
      
      # Source environment files FIRST (before any operations that need them)
      [ -f "$STACKS_DIR/.env-files/wi.env" ] && source "$STACKS_DIR/.env-files/wi.env"
      
      # Clear any WSL Docker environment variables
      # Check if we have a native Docker socket
      if [[ -S /var/run/docker.sock ]]; then
        unset DOCKER_HOST
        unset DOCKER_TLS_VERIFY
        unset DOCKER_CERT_PATH
        export DOCKER_HOST=""
      fi
      
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
      # Check if we have a native Docker socket
      if [[ -S /var/run/docker.sock ]]; then
        unset DOCKER_HOST
        unset DOCKER_TLS_VERIFY
        unset DOCKER_CERT_PATH
        export DOCKER_HOST=""
      fi
      
      [ -f "$STACKS_DIR/.env-files/wi.env" ] && source "$STACKS_DIR/.env-files/wi.env"
      
      cd "$CDK8S_DIR" && npm run synth
      local result=$?
      [ $result -eq 0 ] && echo "✅ Synthesis complete. Manifests in: $CDK8S_DIR/dist/"
      
      cd "$ORIG_DIR"
      return $result
    }
    
    cluster-recreate() {
      # Check Azure authentication first (required for JWKS sync)
      echo "🔐 Checking Azure authentication..."
      check-azure-auth || return 1
      echo ""
      
      # Clear any WSL Docker environment variables
      # Check if we have a native Docker socket
      if [[ -S /var/run/docker.sock ]]; then
        unset DOCKER_HOST
        unset DOCKER_TLS_VERIFY
        unset DOCKER_CERT_PATH
        export DOCKER_HOST=""
      fi
      
      echo "🗑️  Deleting existing cluster..."
      idpbuilder delete || kind delete cluster --name local
      sleep 3
      
      # Call cluster-deploy with flag to skip redundant auth check
      SKIP_AZURE_CHECK=true cluster-deploy "$@"
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
      
      # Get Azure status for display
      local azure_status=$(get-azure-status)
      
      # Option to show logs by default
      local SHOW_LOGS=''${CLUSTER_MENU_LOGS:-true}
      
      local ACTION=$(${pkgs.gum}/bin/gum choose \
        --header "🚀 Cluster Management | Azure: $azure_status" \
        "Synthesize Only" \
        "Synthesize & Deploy (spinner)" \
        "Synthesize & Deploy (with logs)" \
        "Recreate Cluster" \
        "Show Status" \
        "Azure Login/Refresh" \
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
        "Azure Login/Refresh")
          check-azure-auth
          echo ""
          ${pkgs.gum}/bin/gum style --foreground 82 "Press Enter to continue..."
          read -r
          cluster-menu  # Re-run menu
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
    clb = "chromium-dev";  # Cluster browser with dev profile
  };
  
  programs.zsh.shellAliases = config.programs.bash.shellAliases;
  
  home.packages = with pkgs; [ gum ];
  
  home.sessionVariables = {
    STACKS_DIR = "$HOME/stacks";
  };
}