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
    
    cluster-update-gum() {
      # Interactive cluster update using gum
      local REF_DIR="$STACKS_DIR/ref-implementation"
      local CDK8S_DIR="$STACKS_DIR/cdk8s"
      local CLUSTER_NAME="local"
      local ORIG_DIR="$(pwd)"

      # Source environment files (needed for CDK8s synthesis)
      [ -f "$STACKS_DIR/.env-files/wi.env" ] && source "$STACKS_DIR/.env-files/wi.env"

      # Clear Docker environment
      unset DOCKER_HOST DOCKER_TLS_VERIFY DOCKER_CERT_PATH

      # Check cluster exists
      if ! kubectl cluster-info &>/dev/null; then
        ${pkgs.gum}/bin/gum style --foreground 196 "❌ No cluster found. Please create a cluster first."
        return 1
      fi

      # Step 1: Synthesis with progress
      ${pkgs.gum}/bin/gum style --border double --padding "1 2" --border-foreground 212 \
        "🔨 CDK8s Synthesis" \
        "Generating Kubernetes manifests..."

      # Initialize git tracking if needed
      if [ ! -d "$CDK8S_DIR/dist/.git" ]; then
        cd "$CDK8S_DIR/dist" && git init -q && git add -A && git commit -q -m "Initial" 2>/dev/null
        cd "$ORIG_DIR"
      fi

      # Save pre-synthesis state
      cd "$CDK8S_DIR/dist"
      git add -A && git commit -q -m "Pre-synthesis" 2>/dev/null || true

      # Run synthesis with spinner
      cd "$CDK8S_DIR"
      ${pkgs.gum}/bin/gum spin --spinner dot --title "Synthesizing manifests..." -- npm run synth || {
        ${pkgs.gum}/bin/gum style --foreground 196 "❌ Synthesis failed"
        cd "$ORIG_DIR"
        return 1
      }

      # Check for changes
      cd "$CDK8S_DIR/dist"
      local DIFF_FILE="/tmp/cluster-update-diff-$$.txt"
      local CHANGES=""

      if git diff HEAD 2>/dev/null > "$DIFF_FILE" && [ -s "$DIFF_FILE" ]; then
        CHANGES="yes"
        local STATS=$(git diff --stat HEAD | tail -1)

        # Show changes summary with gum
        ${pkgs.gum}/bin/gum style --border rounded --padding "1 2" --border-foreground 214 \
          "📊 Manifest Changes Detected" \
          "" \
          "$STATS"

        # Interactive options
        local VIEW_ACTION=$(${pkgs.gum}/bin/gum choose \
          --header "What would you like to do?" \
          "Continue with update" \
          "View diff summary" \
          "View detailed diff" \
          "Cancel update")

        case "$VIEW_ACTION" in
          "View diff summary")
            git diff --stat HEAD | ${pkgs.gum}/bin/gum pager
            # Ask again after viewing
            if ! ${pkgs.gum}/bin/gum confirm "Continue with update?"; then
              rm -f "$DIFF_FILE"
              return 0
            fi
            ;;
          "View detailed diff")
            if command -v bat &>/dev/null; then
              bat --style=changes --language=diff "$DIFF_FILE"
            else
              ${pkgs.gum}/bin/gum pager < "$DIFF_FILE"
            fi
            if ! ${pkgs.gum}/bin/gum confirm "Continue with update?"; then
              rm -f "$DIFF_FILE"
              return 0
            fi
            ;;
          "Cancel update")
            ${pkgs.gum}/bin/gum style --foreground 226 "⚠️  Update cancelled"
            rm -f "$DIFF_FILE"
            return 0
            ;;
        esac

        # Commit changes
        git add -A && git commit -q -m "Post-synthesis $(date +%Y-%m-%d_%H:%M:%S)" 2>/dev/null
      else
        ${pkgs.gum}/bin/gum style --foreground 82 "✅ No manifest changes detected"
      fi

      cd "$ORIG_DIR"

      # Step 2: Update cluster
      local CONFIG_FILE="$REF_DIR/kind-config-linux-ssh.yaml"
      local LOG_FILE="/tmp/idpbuilder-update-$$.log"

      ${pkgs.gum}/bin/gum style --border double --padding "1 2" --border-foreground 212 \
        "🔄 Cluster Update" \
        "Applying changes with idpbuilder..."

      # Run update with live log viewing option
      local UPDATE_VIEW=$(${pkgs.gum}/bin/gum choose \
        --header "How would you like to monitor the update?" \
        "Show progress only" \
        "Show filtered logs" \
        "Show all logs" \
        "Run in background")

      case "$UPDATE_VIEW" in
        "Show progress only")
          ${pkgs.gum}/bin/gum spin --spinner pulse --title "Updating cluster..." -- \
            bash -c "idpbuilder create \
              --name \"$CLUSTER_NAME\" \
              --kind-config \"$CONFIG_FILE\" \
              --dev-password \
              -p \"$CDK8S_DIR/dist/\" \
              -p \"$REF_DIR/\" &> \"$LOG_FILE\""
          ;;
        "Show filtered logs")
          idpbuilder create \
            --name "''${CLUSTER_NAME}" \
            --kind-config "''${CONFIG_FILE}" \
            --dev-password \
            -p "$CDK8S_DIR/dist/" \
            -p "$REF_DIR/" 2>&1 | tee "$LOG_FILE" | \
          grep -E "(ERROR|Warning|Successfully|Created|Updated|Applied)" | \
          ${pkgs.gum}/bin/gum pager
          ;;
        "Show all logs")
          idpbuilder create \
            --name "''${CLUSTER_NAME}" \
            --kind-config "''${CONFIG_FILE}" \
            --dev-password \
            -p "$CDK8S_DIR/dist/" \
            -p "$REF_DIR/" 2>&1 | tee "$LOG_FILE" | \
          ${pkgs.gum}/bin/gum pager
          ;;
        "Run in background")
          ${pkgs.gum}/bin/gum style --foreground 226 "📝 Logs: tail -f $LOG_FILE"
          idpbuilder create \
            --name "''${CLUSTER_NAME}" \
            --kind-config "''${CONFIG_FILE}" \
            --dev-password \
            -p "$CDK8S_DIR/dist/" \
            -p "$REF_DIR/" &> "$LOG_FILE" &
          local PID=$!
          ${pkgs.gum}/bin/gum spin --spinner line --title "Update running in background (PID: $PID)" \
            -- sleep 5
          ;;
      esac

      local result=$?

      # Show final status
      if [ $result -eq 0 ]; then
        if [ -n "$CHANGES" ]; then
          ${pkgs.gum}/bin/gum style --border double --padding "1 2" --border-foreground 82 \
            "✅ UPDATE COMPLETE" \
            "" \
            "Manifest changes deployed successfully"
        else
          ${pkgs.gum}/bin/gum style --border double --padding "1 2" --border-foreground 82 \
            "✅ UPDATE COMPLETE" \
            "" \
            "Cluster is up-to-date"
        fi
      else
        ${pkgs.gum}/bin/gum style --border double --padding "1 2" --border-foreground 196 \
          "❌ UPDATE FAILED" \
          "" \
          "Check logs: $LOG_FILE"
      fi

      # Offer post-update actions
      local POST_ACTION=$(${pkgs.gum}/bin/gum choose \
        --header "Post-update actions:" \
        "View cluster status" \
        "View update logs" \
        "Run another update" \
        "Exit")

      case "$POST_ACTION" in
        "View cluster status")
          cluster-status | ${pkgs.gum}/bin/gum pager
          ;;
        "View update logs")
          ${pkgs.gum}/bin/gum pager < "$LOG_FILE"
          ;;
        "Run another update")
          cluster-update-gum
          ;;
      esac

      # Cleanup
      rm -f "$DIFF_FILE" 2>/dev/null
      ( sleep 300 && rm -f "$LOG_FILE" 2>/dev/null ) &

      return $result
    }

    cluster-update() {
      # Update existing cluster with idpbuilder (idempotent operation)
      local REF_DIR="$STACKS_DIR/ref-implementation"
      local CDK8S_DIR="$STACKS_DIR/cdk8s"
      local CLUSTER_NAME="local"
      local NO_EXIT=""
      local ORIG_DIR="$(pwd)"

      # Check for --no-exit flag
      if [[ "$1" == "--no-exit" ]]; then
        NO_EXIT="--no-exit"
        shift
      fi

      # Source environment files FIRST (needed for CDK8s synthesis)
      [ -f "$STACKS_DIR/.env-files/wi.env" ] && {
        echo "📋 Loading environment from wi.env..."
        source "$STACKS_DIR/.env-files/wi.env"
      }

      # Clear any WSL Docker environment variables
      if [[ -S /var/run/docker.sock ]]; then
        unset DOCKER_HOST
        unset DOCKER_TLS_VERIFY
        unset DOCKER_CERT_PATH
        export DOCKER_HOST=""
      fi

      # Check if cluster exists
      if ! kubectl cluster-info &>/dev/null; then
        echo "❌ No cluster found. Please create a cluster first with 'cld' or 'cluster-deploy'"
        return 1
      fi

      # Step 1: Synthesize CDK8s manifests (with environment variables)
      echo "🔨 Synthesizing CDK8s manifests..."

      # Initialize git in dist if not already present (for change tracking)
      if [ ! -d "$CDK8S_DIR/dist/.git" ]; then
        cd "$CDK8S_DIR/dist" && git init -q && git add -A && git commit -q -m "Initial commit" 2>/dev/null || true
        cd "$ORIG_DIR"
      fi

      # Save current state of manifests for comparison
      cd "$CDK8S_DIR/dist"
      git add -A 2>/dev/null || true
      git commit -q -m "Pre-synthesis state" 2>/dev/null || true

      # Run synthesis
      cd "$CDK8S_DIR"
      npm run synth || {
        echo "❌ CDK8s synthesis failed"
        cd "$ORIG_DIR"
        return 1
      }

      # Check for changes and display them immediately
      cd "$CDK8S_DIR/dist"
      local DIFF_FILE="/tmp/cluster-update-diff-$$.txt"
      local CHANGES=""

      # Capture the diff and show summary immediately
      if git diff HEAD 2>/dev/null | head -1000 > "$DIFF_FILE" && [ -s "$DIFF_FILE" ]; then
        CHANGES="yes"

        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📊 MANIFEST CHANGES DETECTED"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        # Show summary immediately
        git diff --stat HEAD | head -20

        # Save full summary for later
        echo "=== MANIFEST CHANGES SUMMARY ===" > "''${DIFF_FILE}.summary"
        git diff --stat HEAD >> "''${DIFF_FILE}.summary" 2>/dev/null
        echo "" >> "''${DIFF_FILE}.summary"

        # Offer immediate diff viewing (non-watch mode only)
        if [[ "$NO_EXIT" != "--no-exit" ]]; then
          echo ""
          echo -n "View detailed diff now? [y/N] "
          read -r -t 3 -n 1 response || response="n"
          echo ""

          if [[ "$response" =~ ^[Yy]$ ]]; then
            if command -v bat &>/dev/null; then
              bat --style=changes --paging=always --language=diff "$DIFF_FILE"
            elif command -v less &>/dev/null; then
              less -R "$DIFF_FILE"
            else
              cat "$DIFF_FILE" | head -100
            fi
          fi
        fi

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        # Commit the changes for next comparison
        git add -A && git commit -q -m "Post-synthesis $(date +%Y-%m-%d_%H:%M:%S)" 2>/dev/null || true
      else
        echo ""
        echo "✅ No manifest changes detected"
        rm -f "$DIFF_FILE" 2>/dev/null
      fi

      cd "$ORIG_DIR"

      # Build the kind config path
      local CONFIG_FILE="$REF_DIR/kind-config-linux-ssh.yaml"
      if [ ! -f "$CONFIG_FILE" ]; then
        echo "❌ Kind config not found at: $CONFIG_FILE"
        return 1
      fi

      echo ""
      echo "🔄 Starting cluster update with idpbuilder..."
      echo "📦 Packages: $CDK8S_DIR/dist/ + $REF_DIR/"
      echo ""

      # Create a log file for full output
      local LOG_FILE="/tmp/idpbuilder-update-$$.log"
      echo "📝 Full logs: tail -f $LOG_FILE"
      echo ""

      # Run idpbuilder with limited output display
      # Show only key status lines and errors
      {
        idpbuilder create \
          --name "''${CLUSTER_NAME}" \
          --kind-config "''${CONFIG_FILE}" \
          --dev-password \
          -p "$CDK8S_DIR/dist/" \
          -p "$REF_DIR/" \
          $NO_EXIT "$@" 2>&1 | tee "$LOG_FILE" | {
            # Filter output to show only important lines
            while IFS= read -r line; do
              # Show errors, warnings, and key status updates
              if [[ "$line" =~ (ERROR|Error|FAILED|Failed|failed) ]] || \
                 [[ "$line" =~ (WARNING|Warning) ]] || \
                 [[ "$line" =~ (Successfully|Completed|Created|Updated|Applied) ]] || \
                 [[ "$line" =~ (Syncing|Installing|Deploying|Processing) ]] || \
                 [[ "$line" =~ ^(Creating|Updating|Applying) ]]; then
                echo "  ▸ $line"
              elif [[ "$line" =~ "%" ]]; then
                # Show progress percentages on same line
                echo -ne "\r  ▸ $line"
              fi
            done
            echo ""  # Final newline
          }
      }

      local result=''${PIPESTATUS[0]}

      # Cleanup temp files
      if [ -f "$DIFF_FILE" ]; then
        rm -f "$DIFF_FILE" "''${DIFF_FILE}.summary" 2>/dev/null
      fi

      # Cleanup log file after a delay (keep for debugging)
      ( sleep 300 && rm -f "$LOG_FILE" 2>/dev/null ) &

      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

      if [ $result -eq 0 ]; then
        if [ -n "$CHANGES" ]; then
          echo "✅ UPDATE COMPLETE: Manifest changes deployed successfully"
        else
          echo "✅ UPDATE COMPLETE: No changes needed (cluster is up-to-date)"
        fi

      else
        echo "❌ UPDATE FAILED: Check $LOG_FILE for details"
      fi

      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

      # If no-exit mode, remind user how to stop
      if [ -n "$NO_EXIT" ] && [ $result -eq 0 ]; then
        echo ""
        echo "⏳ Watch mode active - monitoring for changes (Ctrl+C to stop)"
      fi

      cd "$ORIG_DIR"
      return $result
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
        "Update Cluster" \
        "Update Cluster (watch mode)" \
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
        "Update Cluster")
          cluster-update-gum
          ;;
        "Update Cluster (watch mode)")
          ${pkgs.gum}/bin/gum style --foreground 45 "📌 Watch mode will continuously sync changes"
          if ${pkgs.gum}/bin/gum confirm "Start watching for changes?"; then
            echo "🔄 Starting cluster update in watch mode..."
            echo "Press Ctrl+C to stop watching"
            echo ""
            cluster-update --no-exit
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
    clu = "cluster-update";  # Update cluster (idempotent)
    cluw = "cluster-update --no-exit";  # Update cluster in watch mode
    clug = "cluster-update-gum";  # Interactive gum version
    clr = "cluster-recreate";
    clst = "cluster-status";
    clm = "cluster-menu";  # Interactive menu
    clb = "chromium";  # Cluster browser (certificates handled by NSS)
  };
  
  programs.zsh.shellAliases = config.programs.bash.shellAliases;
  
  home.packages = with pkgs; [ gum ];
  
  home.sessionVariables = {
    STACKS_DIR = "$HOME/stacks";
  };
}