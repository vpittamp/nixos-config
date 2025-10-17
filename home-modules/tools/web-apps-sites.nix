# Web Application Sites Configuration
# Declarative definitions for web applications to be launched as standalone apps
# Chromium-based equivalents of Firefox PWAs from pwa-sites.nix
{ config, lib, pkgs, ... }:

{
  programs.webApps = {
    enable = false;  # DISABLED - Using Firefox PWAs instead (better 1Password integration)
    browser = "chromium";  # Use system chromium from chromium.nix

    applications = {
      # AI & Search
      google-ai = {
        name = "Google AI";
        url = "https://www.google.com/search?udm=50";
        wmClass = "webapp-google-ai";
        icon = ../../assets/pwa-icons/google.png;
        workspace = "2";
        lifecycle = "persistent";
        keywords = [ "search" "web" "ai" "google" ];
        enabled = true;
      };

      # Media
      youtube = {
        name = "YouTube";
        url = "https://www.youtube.com";
        wmClass = "webapp-youtube";
        icon = ../../assets/pwa-icons/youtube.png;
        workspace = "3";
        lifecycle = "persistent";
        keywords = [ "video" "streaming" "media" ];
        enabled = true;
      };

      # Development Tools
      gitea = {
        name = "Gitea";
        url = "https://gitea.cnoe.localtest.me:8443";
        wmClass = "webapp-gitea";
        icon = ../../assets/pwa-icons/gitea.png;
        workspace = "4";
        lifecycle = "persistent";
        keywords = [ "git" "code" "repository" ];
        enabled = true;
      };

      backstage = {
        name = "Backstage";
        url = "https://cnoe.localtest.me:8443";
        wmClass = "webapp-backstage";
        icon = ../../assets/pwa-icons/backstage.png;
        workspace = "5";
        lifecycle = "persistent";
        keywords = [ "portal" "platform" "developer" ];
        enabled = true;
      };

      kargo = {
        name = "Kargo";
        url = "https://kargo.cnoe.localtest.me:8443";
        wmClass = "webapp-kargo";
        icon = ../../assets/pwa-icons/kargo.png;
        workspace = "6";
        lifecycle = "persistent";
        keywords = [ "gitops" "deployment" "kubernetes" ];
        enabled = true;
      };

      argocd = {
        name = "ArgoCD";
        url = "https://argocd.cnoe.localtest.me:8443";
        wmClass = "webapp-argocd";
        icon = ../../assets/pwa-icons/argocd.png;
        workspace = "7";
        lifecycle = "persistent";
        keywords = [ "gitops" "cd" "kubernetes" "deployment" ];
        enabled = true;
      };

      github-codespaces = {
        name = "GitHub Codespaces";
        url = "https://github.com/codespaces";
        wmClass = "webapp-github-codespaces";
        icon = ../../assets/pwa-icons/github-codespaces.png;
        workspace = "8";
        lifecycle = "persistent";
        keywords = [ "github" "codespaces" "cloud" "ide" ];
        enabled = true;
      };

      chatgpt-codex = {
        name = "ChatGPT Codex";
        url = "https://chatgpt.com/codex";
        wmClass = "webapp-chatgpt-codex";
        icon = ../../assets/pwa-icons/chatgpt-codex.png;
        workspace = "9";
        lifecycle = "persistent";
        keywords = [ "ai" "chatgpt" "codex" "coding" "assistant" ];
        enabled = true;
      };

      # Infrastructure & Cloud
      home-assistant = {
        name = "Home Assistant";
        url = "http://localhost:8123";
        wmClass = "webapp-home-assistant";
        icon = ../../assets/pwa-icons/home-assistant.png;
        workspace = null;  # No auto workspace assignment
        lifecycle = "persistent";
        keywords = [ "home" "automation" "smart" "iot" "assistant" ];
        enabled = true;
      };

      azure-portal = {
        name = "Azure Portal";
        url = "https://portal.azure.com";
        wmClass = "webapp-azure-portal";
        icon = ../../assets/pwa-icons/azure.png;
        workspace = null;
        lifecycle = "persistent";
        keywords = [ "azure" "cloud" "microsoft" "portal" ];
        enabled = true;
      };

      hetzner-cloud = {
        name = "Hetzner Cloud";
        url = "https://console.hetzner.cloud";
        wmClass = "webapp-hetzner-cloud";
        icon = ../../assets/pwa-icons/hetzner.png;
        workspace = null;
        lifecycle = "persistent";
        keywords = [ "hetzner" "cloud" "vps" "server" ];
        enabled = true;
      };

      tailscale = {
        name = "Tailscale";
        url = "https://login.tailscale.com/admin/machines";
        wmClass = "webapp-tailscale";
        icon = ../../assets/pwa-icons/tailscale.png;
        workspace = null;
        lifecycle = "persistent";
        keywords = [ "vpn" "tailscale" "network" "admin" ];
        enabled = true;
      };

      # Lifestyle
      uber-eats = {
        name = "Uber Eats";
        url = "https://www.ubereats.com";
        wmClass = "webapp-uber-eats";
        icon = ../../assets/pwa-icons/uber-eats.png;
        workspace = null;
        lifecycle = "persistent";
        keywords = [ "food" "delivery" "restaurant" "uber" ];
        enabled = true;
      };
    };

    i3Integration = {
      autoAssignWorkspace = true;
      floatingMode = false;
    };

    rofi = {
      showIcons = true;
    };
  };
}
