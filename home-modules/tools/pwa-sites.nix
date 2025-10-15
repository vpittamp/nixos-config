# Centralized PWA Site Definitions
# This module defines all PWA sites in one place for reuse across:
# - firefox-pwas-declarative.nix (PWA installation)
# - firefox.nix (tracking protection exceptions, clipboard permissions)
# - Any future PWA-related configuration

{ lib, ... }:

{
  # PWA site definitions with all metadata
  pwaSites = [
    {
      name = "Google AI";
      url = "https://www.google.com/search?udm=50";
      domain = "google.com";
      icon = "file:///etc/nixos/assets/pwa-icons/google.png";
      description = "Google AI Search";
      categories = "Network;WebBrowser;";
      keywords = "search;web;ai;";
    }
    {
      name = "YouTube";
      url = "https://www.youtube.com";
      domain = "youtube.com";
      icon = "file:///etc/nixos/assets/pwa-icons/youtube.png";
      description = "YouTube Video Platform";
      categories = "AudioVideo;Video;";
      keywords = "video;streaming;";
    }
    {
      name = "Gitea";
      url = "https://gitea.cnoe.localtest.me:8443";
      domain = "gitea.cnoe.localtest.me";
      icon = "file:///etc/nixos/assets/pwa-icons/gitea.png";
      description = "Git Repository Management";
      categories = "Development;";
      keywords = "git;code;repository;";
    }
    {
      name = "Backstage";
      url = "https://cnoe.localtest.me:8443";
      domain = "cnoe.localtest.me";
      icon = "file:///etc/nixos/assets/pwa-icons/backstage.png";
      description = "Developer Portal";
      categories = "Development;";
      keywords = "portal;platform;developer;";
    }
    {
      name = "Kargo";
      url = "https://kargo.cnoe.localtest.me:8443";
      domain = "kargo.cnoe.localtest.me";
      icon = "file:///etc/nixos/assets/pwa-icons/kargo.png";
      description = "GitOps Promotion";
      categories = "Development;";
      keywords = "gitops;deployment;kubernetes;";
    }
    {
      name = "ArgoCD";
      url = "https://argocd.cnoe.localtest.me:8443";
      domain = "argocd.cnoe.localtest.me";
      icon = "file:///etc/nixos/assets/pwa-icons/argocd.png";
      description = "GitOps Continuous Delivery";
      categories = "Development;";
      keywords = "gitops;cd;kubernetes;deployment;";
    }
    {
      name = "Home Assistant";
      url = "http://localhost:8123";
      domain = "localhost";
      icon = "file:///etc/nixos/assets/pwa-icons/home-assistant.png";
      description = "Home Automation Platform";
      categories = "Network;RemoteAccess;";
      keywords = "home;automation;smart;iot;assistant;";
    }
    {
      name = "Uber Eats";
      url = "https://www.ubereats.com";
      domain = "ubereats.com";
      icon = "file:///etc/nixos/assets/pwa-icons/uber-eats.png";
      description = "Food Delivery Service";
      categories = "Network;Office;";
      keywords = "food;delivery;restaurant;uber;";
    }
    {
      name = "GitHub Codespaces";
      url = "https://github.com/codespaces";
      domain = "github.com";
      icon = "file:///etc/nixos/assets/pwa-icons/github-codespaces.png";
      description = "GitHub Cloud Development Environment";
      categories = "Development;";
      keywords = "github;codespaces;cloud;ide;";
    }
    {
      name = "Azure Portal";
      url = "https://portal.azure.com";
      domain = "azure.com";
      scope = "https://portal.azure.com/";
      icon = "file:///etc/nixos/assets/pwa-icons/azure.png";
      description = "Microsoft Azure Cloud Portal";
      categories = "Network;System;";
      keywords = "azure;cloud;microsoft;portal;";
    }
    {
      name = "Hetzner Cloud";
      url = "https://console.hetzner.cloud";
      domain = "hetzner.cloud";
      scope = "https://console.hetzner.cloud/";
      icon = "file:///etc/nixos/assets/pwa-icons/hetzner.png";
      description = "Hetzner Cloud Console";
      categories = "Network;System;";
      keywords = "hetzner;cloud;vps;server;";
    }
    {
      name = "ChatGPT Codex";
      url = "https://chatgpt.com/codex";
      domain = "chatgpt.com";
      icon = "file:///etc/nixos/assets/pwa-icons/chatgpt-codex.png";
      description = "ChatGPT Code Assistant";
      categories = "Development;";
      keywords = "ai;chatgpt;codex;coding;assistant;";
    }
    {
      name = "Tailscale";
      url = "https://login.tailscale.com/admin/machines";
      domain = "login.tailscale.com";
      scope = "https://login.tailscale.com/";
      icon = "file:///etc/nixos/assets/pwa-icons/tailscale.png";
      description = "Tailscale VPN Admin Console";
      categories = "Network;System;";
      keywords = "vpn;tailscale;network;admin;";
    }
  ];

  # Additional trusted domains for Firefox policies
  # These are domains that need clipboard/tracking exception but aren't PWAs
  additionalTrustedDomains = [
    # GitHub ecosystem
    "github.dev"
    "codespaces.githubusercontent.com"

    # AI tools
    "claude.ai"

    # Authentication
    "my.1password.com"
    "1password.com"
  ];

  # Helper functions to extract domain patterns for Firefox policies
  helpers = {
    # Extract unique base domains from PWA sites
    # Returns list like: ["google.com", "youtube.com", "github.com", ...]
    getBaseDomains = sites: lib.unique (map (site: site.domain) sites);

    # Generate Firefox policy exception patterns
    # Returns list like: ["https://google.com", "https://*.google.com", ...]
    getDomainPatterns = sites: additionalDomains:
      let
        pwaDomains = lib.unique (map (site: site.domain) sites);
        allDomains = lib.unique (pwaDomains ++ additionalDomains);

        # Generate both exact and wildcard patterns for each domain
        generatePatterns = domain:
          if lib.hasPrefix "localhost" domain || lib.hasPrefix "127.0.0.1" domain
          then [ "http://${domain}" ]  # localhost uses HTTP
          else [
            "https://${domain}"
            "https://*.${domain}"
          ];
      in
        lib.flatten (map generatePatterns allDomains);
  };
}
