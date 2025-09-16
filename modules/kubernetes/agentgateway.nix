# AgentGateway Configuration for Kubernetes
# Provides AI-aware gateway functionality with xDS-based configuration
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.agentgateway;
  
  # Helm values for AgentGateway deployment
  helmValues = ''
    agentGateway:
      enabled: true
      
    # Image configuration
    image:
      repository: ghcr.io/kgateway-dev/kgateway
      tag: latest
      pullPolicy: IfNotPresent
    
    # Gateway configuration
    gateway:
      gatewayClassName: agentgateway
      listeners:
        - name: http
          protocol: HTTP
          port: 8080
          allowedRoutes:
            namespaces:
              from: All
        - name: https
          protocol: HTTPS
          port: 8443
          allowedRoutes:
            namespaces:
              from: All
    
    # Service configuration
    service:
      type: LoadBalancer
      ports:
        - name: http
          port: 8080
          targetPort: 8080
        - name: https
          port: 8443
          targetPort: 8443
    
    # Resource limits
    resources:
      requests:
        memory: "128Mi"
        cpu: "100m"
      limits:
        memory: "512Mi"
        cpu: "500m"
    
    # Enable AI backend routing capabilities
    aiBackends:
      enabled: true
      providers:
        - name: openai
          type: openai
          configSecretRef:
            name: openai-config
        - name: anthropic
          type: anthropic
          configSecretRef:
            name: anthropic-config
  '';
  
  # Script to deploy AgentGateway
  deployScript = pkgs.writeScriptBin "deploy-agentgateway" ''
    #!${pkgs.bash}/bin/bash
    set -e
    
    echo "Deploying AgentGateway to Kubernetes..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
      echo "kubectl is not available. Please ensure Kubernetes is configured."
      exit 1
    fi
    
    # Check if cluster is accessible
    if ! kubectl cluster-info &> /dev/null; then
      echo "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
      exit 1
    fi
    
    # Create namespace if it doesn't exist
    kubectl create namespace kgateway-system --dry-run=client -o yaml | kubectl apply -f -
    
    # Install Gateway API CRDs if not already installed
    echo "Installing Gateway API CRDs..."
    kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/experimental-install.yaml || true
    
    # Install kgateway CRDs
    echo "Installing kgateway CRDs..."
    ${pkgs.kubernetes-helm}/bin/helm upgrade --install \
      --create-namespace \
      --namespace kgateway-system \
      --version v2.0.4 \
      kgateway-crds \
      oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds
    
    # Deploy kgateway using Helm with OCI registry
    echo "Deploying kgateway..."
    cat <<EOF | ${pkgs.kubernetes-helm}/bin/helm upgrade --install \
      --namespace kgateway-system \
      --version v2.0.4 \
      --values - \
      kgateway \
      oci://cr.kgateway.dev/kgateway-dev/charts/kgateway
    ${helmValues}
    EOF
    
    echo "kgateway deployment initiated. Checking status..."
    kubectl -n kgateway-system rollout status deployment/kgateway-controller --timeout=300s || true
    
    echo "kgateway pods:"
    kubectl -n kgateway-system get pods
    
    echo "Gateway resources:"
    kubectl get gateways -A
  '';
  
  # Script to create AI backend secrets
  createSecretsScript = pkgs.writeScriptBin "create-ai-secrets" ''
    #!${pkgs.bash}/bin/bash
    set -e
    
    echo "Creating AI backend secrets for AgentGateway..."
    
    # Create OpenAI secret (fetch from 1Password if available)
    if command -v op &> /dev/null; then
      OPENAI_KEY=$(op read "op://Personal/OpenAI API Key/credential" 2>/dev/null || echo "")
      if [ -n "$OPENAI_KEY" ]; then
        kubectl create secret generic openai-config \
          --namespace agentgateway \
          --from-literal=api-key="$OPENAI_KEY" \
          --dry-run=client -o yaml | kubectl apply -f -
        echo "OpenAI secret created from 1Password"
      else
        echo "OpenAI API key not found in 1Password"
      fi
    fi
    
    # Create Anthropic secret (fetch from 1Password if available)
    if command -v op &> /dev/null; then
      ANTHROPIC_KEY=$(op read "op://Personal/Anthropic API Key/credential" 2>/dev/null || echo "")
      if [ -n "$ANTHROPIC_KEY" ]; then
        kubectl create secret generic anthropic-config \
          --namespace agentgateway \
          --from-literal=api-key="$ANTHROPIC_KEY" \
          --dry-run=client -o yaml | kubectl apply -f -
        echo "Anthropic secret created from 1Password"
      else
        echo "Anthropic API key not found in 1Password"
      fi
    fi
  '';
  
  # Sample HTTPRoute for AI services
  sampleRouteScript = pkgs.writeScriptBin "apply-ai-route" ''
    #!${pkgs.bash}/bin/bash
    echo "Applying sample AI route configuration..."
    cat <<'EOF' | kubectl apply -f -
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: ai-route
      namespace: default
    spec:
      parentRefs:
      - name: agentgateway
        namespace: agentgateway
      hostnames:
      - "ai.local"
      rules:
      - matches:
        - path:
            type: PathPrefix
            value: /openai
        backendRefs:
        - name: openai
          namespace: agentgateway
          kind: Service
          port: 443
      - matches:
        - path:
            type: PathPrefix
            value: /anthropic
        backendRefs:
        - name: anthropic
          namespace: agentgateway
          kind: Service
          port: 443
    EOF
    echo "AI route applied successfully"
  '';

in
{
  options.services.agentgateway = {
    enable = mkEnableOption "AgentGateway for Kubernetes";
    
    autoDeployOnBoot = mkOption {
      type = types.bool;
      default = false;
      description = "Automatically deploy AgentGateway when the system boots";
    };
    
    enableAIBackends = mkOption {
      type = types.bool;
      default = true;
      description = "Enable AI backend routing capabilities";
    };
  };
  
  config = mkIf cfg.enable {
    # Add required packages
    environment.systemPackages = with pkgs; [
      kubernetes-helm
      kubectl
      deployScript
      createSecretsScript
    ] ++ lib.optional cfg.enableAIBackends sampleRouteScript;
    
    # Create systemd service for auto-deployment
    systemd.services.agentgateway-deploy = mkIf cfg.autoDeployOnBoot {
      description = "Deploy AgentGateway to Kubernetes";
      after = [ "network-online.target" "docker.service" ];
      wants = [ "network-online.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "vpittamp";  # Run as user to access kubeconfig
        ExecStart = "${deployScript}/bin/deploy-agentgateway";
        ExecStartPre = "${pkgs.bash}/bin/bash -c 'until kubectl cluster-info &>/dev/null; do echo Waiting for cluster...; sleep 5; done'";
      };
      
      # Only run if Kind or Kubernetes is available
      unitConfig = {
        ConditionPathExists = "/home/vpittamp/.kube/config";
      };
    };
    
    # Add shell aliases for convenience
    programs.bash.shellAliases = {
      ag-deploy = "deploy-agentgateway";
      ag-secrets = "create-ai-secrets";
      ag-status = "kubectl -n agentgateway get all";
      ag-logs = "kubectl -n agentgateway logs -l app=agentgateway --tail=100 -f";
      ag-route = "apply-ai-route";
    };
    
    # Documentation
    environment.etc."agentgateway/README.md".text = ''
      # AgentGateway Configuration
      
      AgentGateway is deployed and managed through this NixOS module.
      
      ## Quick Start
      
      1. Deploy AgentGateway:
         ```bash
         ag-deploy  # or deploy-agentgateway
         ```
      
      2. Create AI backend secrets (from 1Password):
         ```bash
         ag-secrets  # or create-ai-secrets
         ```
      
      3. Check status:
         ```bash
         ag-status
         ```
      
      4. View logs:
         ```bash
         ag-logs
         ```
      
      5. Apply sample AI route:
         ```bash
         ag-route
         ```
      
      ## Configuration
      
      The AgentGateway is configured to:
      - Listen on ports 8080 (HTTP) and 8443 (HTTPS)
      - Support AI backend routing (OpenAI, Anthropic)
      - Use xDS-based configuration distribution
      - Integrate with Kubernetes Gateway API
      
      ## AI Backend Configuration
      
      API keys are stored as Kubernetes secrets and can be automatically
      populated from 1Password using the `ag-secrets` command.
      
      ## Troubleshooting
      
      - Check pod status: `kubectl -n agentgateway get pods`
      - Check gateway status: `kubectl get gateways -A`
      - Check routes: `kubectl get httproutes -A`
      - View detailed logs: `ag-logs`
    '';
  };
}