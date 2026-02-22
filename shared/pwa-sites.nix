# PWA Site Definitions - Single Source of Truth
# This file contains all PWA metadata with ULID identifiers for cross-machine portability
# Feature 106: Portable icon paths via assetsPackage
# Feature 113: URL routing - routing_domains defines which domains open in this PWA
# Feature 118: Path-based routing (routing_paths) and internal auth (auth_domains)
{ lib, assetsPackage ? null, hostName ? "" }:

let
  # Feature 106: Helper to get icon path from Nix store or fallback to legacy path
  iconPath = name:
    if assetsPackage != null
    then "${assetsPackage}/icons/${name}"
    else "/etc/nixos/assets/icons/${name}";

  # Helper to determine if a PWA should be included for the current host
  # If hostName is empty, all PWAs are included (legacy/global view)
  # If hostName is provided, only global PWAs and host-matching PWAs are included
  shouldInclude = pwa:
    if hostName == "" then true
    else if !(pwa ? host) || pwa.host == "global" || pwa.host == "hub" then true
    else pwa.host == hostName;

  # Helper to format PWA name - remove host suffix if viewing for a specific host
  formatName = pwa:
    if hostName != "" && pwa ? host && pwa.host == hostName && (lib.hasSuffix " ${lib.toUpper (lib.substring 0 1 pwa.host)}${lib.substring 1 (-1) pwa.host}" pwa.name)
    then lib.removeSuffix " ${lib.toUpper (lib.substring 0 1 pwa.host)}${lib.substring 1 (-1) pwa.host}" pwa.name
    # Special case for ThinkPad/Ryzen which I added with specific casing
    else if hostName == "thinkpad" then lib.removeSuffix " ThinkPad" pwa.name
    else if hostName == "ryzen" then lib.removeSuffix " Ryzen" pwa.name
    else pwa.name;

  allPwaSites = [
    # YouTube
    {
      name = "YouTube";
      url = "https://www.youtube.com";
      domain = "youtube.com";
      icon = iconPath "youtube.svg";
      description = "YouTube video platform";
      categories = "AudioVideo;Video;";
      keywords = "video;streaming;youtube;";
      scope = "https://www.youtube.com/";
      ulid = "01K666N2V6BQMDSBMX3AY74TY7";  # FFPWA ID
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 50;
      preferred_monitor_role = "secondary";  # Feature 001: Separate from Firefox (tertiary)
      # Feature 113: URL routing domains
      routing_domains = [ "youtube.com" "www.youtube.com" "youtu.be" "m.youtube.com" ];
      # Feature 118: Auth domains
      auth_domains = [ "accounts.google.com" ];
    }

    # Google AI (AI Mode Search)
    {
      name = "Google AI";
      url = "https://google.com/ai";
      domain = "google.com";
      icon = iconPath "google-ai.png";
      description = "Google AI Mode - Advanced AI search with Gemini 2.5";
      categories = "Network;Development;";
      keywords = "ai;gemini;google;search;assistant;";
      scope = "https://google.com/";
      ulid = "01K665SPD8EPMP3JTW02JM1M0Z";  # FFPWA ID
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 51;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing - only AI-specific paths, not general google.com
      routing_domains = [ ];  # Disabled - google.com is too broad
      routing_paths = [ "/ai" ];  # Match google.com/ai/*
      auth_domains = [ "accounts.google.com" ];
    }

    # Claude (Anthropic AI)
    {
      name = "Claude";
      url = "https://claude.ai/code";
      domain = "claude.ai";
      icon = iconPath "claude.svg";
      description = "Claude AI Assistant by Anthropic";
      categories = "Network;Development;";
      keywords = "ai;claude;anthropic;assistant;";
      scope = "https://claude.ai/";
      ulid = "01JCYF8Z2M7R4N6QW9XKPHVTB5";  # Generated 2025-11-02
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 52;
      preferred_monitor_role = "secondary";  # Feature 001: Explicit secondary assignment (dev tools on center monitor)
      # Feature 113: URL routing domains
      routing_domains = [ "claude.ai" "www.claude.ai" ];
    }

    # ChatGPT
    {
      name = "ChatGPT";
      url = "https://chatgpt.com/codex";
      domain = "chatgpt.com";
      icon = iconPath "chatgpt.svg";
      description = "ChatGPT AI assistant";
      categories = "Network;Development;";
      keywords = "ai;chatgpt;openai;assistant;";
      scope = "https://chatgpt.com/";
      ulid = "01K772ZBM45JD68HXYNM193CVW";  # FFPWA ID
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 53;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "chatgpt.com" "www.chatgpt.com" "chat.openai.com" ];
    }

    # GitHub
    {
      name = "GitHub";
      url = "https://github.com";
      domain = "github.com";
      icon = iconPath "github-mark.png";
      description = "GitHub Code Hosting Platform";
      categories = "Development;Network;";
      keywords = "git;github;code;development;";
      scope = "https://github.com/";
      ulid = "01JCYF9A3P8T5W7XH0KMQRNZC6";  # Generated 2025-11-02
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 54;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "github.com" "www.github.com" ];
    }

    # GitHub Codespaces
    {
      name = "GitHub Codespaces";
      url = "https://github.dev";
      domain = "github.dev";
      icon = iconPath "github-codespaces.svg";
      description = "GitHub cloud development environment";
      categories = "Development;Network;";
      keywords = "github;codespaces;cloud;ide;development;";
      scope = "https://github.dev/";
      ulid = "01K772Z7AY5J36Q3NXHH9RYGC0";  # FFPWA ID
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 55;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "github.dev" ];
    }

    # Gmail
    {
      name = "Gmail";
      url = "https://mail.google.com";
      domain = "mail.google.com";
      icon = iconPath "gmail.svg";
      description = "Google Gmail Email Client";
      categories = "Network;Email;";
      keywords = "email;gmail;google;mail;";
      scope = "https://mail.google.com/";
      ulid = "01JCYF9K4Q9V6X8YJ1MNSPT0D7";  # Generated 2025-11-02
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 56;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "mail.google.com" ];
      # Feature 118: Auth domains
      auth_domains = [ "accounts.google.com" ];
    }

    # Google Calendar
    {
      name = "Google Calendar";
      url = "https://calendar.google.com";
      domain = "calendar.google.com";
      icon = iconPath "google-calendar.svg";
      description = "Google Calendar";
      categories = "Office;Calendar;";
      keywords = "calendar;google;schedule;events;";
      scope = "https://calendar.google.com/";
      ulid = "01JCYF9T5R0W7Y9ZK2PQTVX1E8";  # Generated 2025-11-02
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 57;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "calendar.google.com" ];
      # Feature 118: Auth domains
      auth_domains = [ "accounts.google.com" ];
    }

    # LinkedIn Learning
    {
      name = "LinkedIn Learning";
      url = "https://www.linkedin.com/learning";
      domain = "linkedin.com";
      icon = iconPath "linkedin-learning.svg";
      description = "LinkedIn Learning video courses and skills training";
      categories = "Education;Network;";
      keywords = "learning;courses;linkedin;skills;training;";
      scope = "https://www.linkedin.com/learning";
      ulid = "01K9QA9TKKTYPZ4CTKQVVATD7W";  # Generated 2025-11-10
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 58;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing - only learning subdomain, not all of linkedin
      routing_domains = [ ];  # Disabled - linkedin.com is too broad
      # Feature 118: Path-based routing for /learning paths
      routing_paths = [ "/learning" ];  # Match linkedin.com/learning/*
    }

    # Boston Dog Butlers
    {
      name = "Boston Dog Butlers";
      url = "https://www.timetopet.com/portal/services";
      domain = "bostondogbutlers.com";
      icon = iconPath "boston-dog-butlers.svg";
      description = "Boston Dog Butlers concierge dog walking and care services";
      categories = "Utility;Network;";
      keywords = "dog;pet-care;walking;boston;concierge;";
      scope = "https://bostondogbutlers.com/";
      ulid = "01MD0GBTR2QN6XZ7P8Q9RS3T5V";  # Generated 2025-11-14
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 59;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "bostondogbutlers.com" "www.bostondogbutlers.com" "www.timetopet.com" ];
    }

    # Microsoft Outlook
    {
      name = "Microsoft Outlook";
      url = "https://outlook.office.com/mail";
      domain = "outlook.office.com";
      icon = iconPath "outlook.svg";
      description = "Microsoft Outlook web email client";
      categories = "Network;Email;Office;";
      keywords = "email;outlook;microsoft;office;mail;calendar;";
      scope = "https://outlook.office.com/";
      ulid = "01K9WW04PVPHM40D1PV2RVHZFT";  # Generated 2025-11-12
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 60;
      preferred_monitor_role = "secondary";  # Email client on center monitor
      # Feature 113: URL routing domains
      routing_domains = [ "outlook.office.com" "outlook.live.com" ];
      # Feature 118: Microsoft auth domains
      auth_domains = [ "login.microsoftonline.com" "login.live.com" ];
    }

    # Hetzner Cloud Console
    {
      name = "Hetzner Cloud";
      url = "https://console.hetzner.cloud";
      domain = "console.hetzner.cloud";
      icon = iconPath "hetzner-cloud.svg";
      description = "Hetzner Cloud infrastructure management console";
      categories = "Network;Development;System;";
      keywords = "cloud;infrastructure;server;hosting;hetzner;devops;";
      scope = "https://console.hetzner.cloud/";
      ulid = "01K9WW04PVCDRTE4WFFPCYC436";  # Generated 2025-11-12
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 61;
      preferred_monitor_role = "tertiary";  # Infrastructure tools on tertiary monitor
      # Feature 113: URL routing domains
      routing_domains = [ "console.hetzner.cloud" ];
    }

    # Tailscale Admin Console
    {
      name = "Tailscale";
      url = "https://login.tailscale.com/admin/machines";
      domain = "login.tailscale.com";
      icon = iconPath "tailscale.svg";
      description = "Tailscale VPN admin console for managing devices and network";
      categories = "Network;System;Security;";
      keywords = "vpn;tailscale;network;mesh;admin;devices;";
      scope = "https://login.tailscale.com/";
      ulid = "01K9YS261RFD4HHDNVGDAV41EG";  # Generated 2025-11-12
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 62;
      preferred_monitor_role = "tertiary";  # Network admin tools on tertiary monitor
      # Feature 113: URL routing domains
      routing_domains = [ "login.tailscale.com" "tailscale.com" "www.tailscale.com" ];
    }

    # Uber Eats
    {
      name = "Uber Eats";
      url = "https://www.ubereats.com";
      domain = "ubereats.com";
      icon = iconPath "ubereats.jpeg";
      description = "Uber Eats food delivery service";
      categories = "Network;Utility;";
      keywords = "food;delivery;ubereats;restaurant;order;";
      scope = "https://www.ubereats.com/";
      ulid = "01MD0VNQPKST6Y7X8Z9ABCDEFH";  # Generated 2025-11-13
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 63;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "ubereats.com" "www.ubereats.com" ];
    }

    # Home Assistant
    {
      name = "Home Assistant";
      url = "http://localhost:8123";
      domain = "localhost";
      icon = iconPath "home-assistant.svg";
      description = "Home Assistant - Open source home automation";
      categories = "Network;Utility;";
      keywords = "home;automation;iot;smart-home;homeassistant;";
      scope = "http://localhost:8123/";
      ulid = "3TH05T0Z8NQQTVZQ86ZNNQDTPA";  # Generated 2025-11-15 (valid ULID format)
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 64;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing - localhost is too generic
      routing_domains = [ ];  # Disabled - localhost:8123 would conflict with other local services
    }

    # 1Password
    {
      name = "1Password";
      url = "https://pittampalli.1password.com/home";
      domain = "pittampalli.1password.com";
      icon = iconPath "1password.svg";
      description = "1Password web application";
      categories = "Network;";
      keywords = "1password;password;vault;security;";
      scope = "https://pittampalli.1password.com/home/";
      ulid = "2V60G2X1JTZRG6Y41YTKRG2WWW";  # Generated 2025-11-15
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 65;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "pittampalli.1password.com" "my.1password.com" ];
    }

    # Perplexity
    {
      name = "Perplexity";
      url = "https://www.perplexity.ai";
      domain = "www.perplexity.ai";
      icon = iconPath "perplexity.svg";
      description = "Perplexity - AI-powered search engine";
      categories = "Network;Development;";
      keywords = "perplexity;ai;search;research;assistant;chatbot;";
      scope = "https://www.perplexity.ai/";
      ulid = "7YFECJA7EMY52HNX7BRFVMJ6MC";  # Generated 2025-11-15 (valid ULID format)
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 66;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "perplexity.ai" "www.perplexity.ai" ];
    }

    # VS Code Web
    {
      name = "VS Code Web";
      url = "https://vscode.dev";
      domain = "vscode.dev";
      icon = iconPath "vscode-dev.svg";
      description = "VS Code for the Web - Online code editor";
      categories = "Development;Network;";
      keywords = "vscode;code;editor;development;web;ide;browser;";
      scope = "https://vscode.dev/";
      ulid = "4RV2WXPQBXGKS37MXKGX451A11";  # Generated 2025-11-15
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 67;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "vscode.dev" "insiders.vscode.dev" ];
    }

    # Keycloak (Ryzen K8s via Tailscale)
    {
      name = "Keycloak";
      url = "https://keycloak-ryzen.tail286401.ts.net";
      domain = "keycloak-ryzen.tail286401.ts.net";
      icon = iconPath "keycloak.svg";
      description = "Keycloak identity and access management";
      categories = "Security;Network;";
      keywords = "keycloak;iam;auth;openid;single-sign-on;kubernetes;";
      scope = "https://keycloak-ryzen.tail286401.ts.net/";
      ulid = "01MD4CZ7H4KJ4TR0C2Q3C8ZQ9V";  # Generated 2025-11-17
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 68;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "keycloak-ryzen.tail286401.ts.net" ];
    }

    # Backstage (Ryzen K8s via Tailscale)
    {
      name = "Backstage";
      url = "https://backstage-ryzen.tail286401.ts.net";
      domain = "backstage-ryzen.tail286401.ts.net";
      icon = iconPath "backstage.svg";
      description = "Backstage developer portal";
      categories = "Development;Network;";
      keywords = "backstage;developer-portal;sdp;platform;kubernetes;";
      scope = "https://backstage-ryzen.tail286401.ts.net/";
      ulid = "01MD4D0A6S2CVXKNNY4EJ5PQ1G";  # Generated 2025-11-17
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 69;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "backstage-ryzen.tail286401.ts.net" ];
    }

    # ArgoCD (Ryzen K8s via Tailscale)
    {
      name = "ArgoCD";
      url = "https://argocd-ryzen.tail286401.ts.net";
      domain = "argocd-ryzen.tail286401.ts.net";
      icon = iconPath "argocd.svg";
      description = "ArgoCD GitOps controller";
      categories = "Development;Network;System;";
      keywords = "argocd;gitops;cd;kubernetes;devops;";
      scope = "https://argocd-ryzen.tail286401.ts.net/";
      ulid = "01MD4D0N7A8F9P6QS0R1TV2WX3";  # Generated 2025-11-17
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 70;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "argocd-ryzen.tail286401.ts.net" ];
    }

    # Argo Workflows (Ryzen K8s via Tailscale)
    {
      name = "Argo Workflows";
      url = "https://argo-workflows-ryzen.tail286401.ts.net";
      domain = "argo-workflows-ryzen.tail286401.ts.net";
      icon = iconPath "argo-workflows.png";
      description = "Argo Workflows - Kubernetes-native workflow engine";
      categories = "Development;Network;System;";
      keywords = "argo;workflows;kubernetes;pipelines;ci;automation;";
      scope = "https://argo-workflows-ryzen.tail286401.ts.net/";
      ulid = "56RN5CMB8EJQ8KEVPWDR2GB7PX";  # Generated 2025-01-29
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 107;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "argo-workflows-ryzen.tail286401.ts.net" ];
    }

    # Gitea (Ryzen K8s via Tailscale)
    {
      name = "Gitea";
      url = "https://gitea-ryzen.tail286401.ts.net";
      domain = "gitea-ryzen.tail286401.ts.net";
      icon = iconPath "gitea.svg";
      description = "Gitea self-hosted git service";
      categories = "Development;Network;";
      keywords = "gitea;git;scm;code;devops;kubernetes;";
      scope = "https://gitea-ryzen.tail286401.ts.net/";
      ulid = "01MD4D14BDS6Z4GMY3K9HFT8PA";  # Generated 2025-11-17
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 71;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "gitea-ryzen.tail286401.ts.net" ];
    }

    # CVS Pharmacy
    {
      name = "CVS Pharmacy";
      url = "https://www.cvs.com";
      domain = "cvs.com";
      icon = iconPath "cvs-pharmacy.svg";
      description = "CVS Pharmacy - Health and wellness retailer";
      categories = "Network;Utility;";
      keywords = "cvs;pharmacy;health;prescriptions;wellness;drugstore;";
      scope = "https://www.cvs.com/";
      ulid = "66X3EWFQ4ZZMEHWY8Q7DWPB6BN";  # Generated 2025-11-17
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 72;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "cvs.com" "www.cvs.com" ];
    }

    # Kargo (Ryzen K8s via Tailscale)
    {
      name = "Kargo";
      url = "https://kargo-ryzen.tail286401.ts.net";
      domain = "kargo-ryzen.tail286401.ts.net";
      icon = iconPath "kargo.png";
      description = "Kargo continuous delivery and promotion engine for Kubernetes";
      categories = "Development;Network;System;";
      keywords = "kargo;kubernetes;cd;gitops;promotion;delivery;";
      scope = "https://kargo-ryzen.tail286401.ts.net/";
      ulid = "01MEQFV8K4N3R7S2T5W9X0Y1Z6";  # Generated 2025-11-18
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 73;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "kargo-ryzen.tail286401.ts.net" ];
    }

    # Headlamp (Ryzen K8s via Tailscale)
    {
      name = "Headlamp";
      url = "https://headlamp-ryzen.tail286401.ts.net";
      domain = "headlamp-ryzen.tail286401.ts.net";
      icon = iconPath "headlamp.svg";
      description = "Headlamp Kubernetes dashboard";
      categories = "Development;Network;System;";
      keywords = "headlamp;kubernetes;dashboard;k8s;cluster;";
      scope = "https://headlamp-ryzen.tail286401.ts.net/";
      ulid = "01MEQFVCK5P4S8T3V6X0Y2Z7A1";  # Generated 2025-11-18
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 74;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "headlamp-ryzen.tail286401.ts.net" ];
    }

    # Kagent (Ryzen K8s via Tailscale)
    {
      name = "Kagent";
      url = "https://kagent-ryzen.tail286401.ts.net";
      domain = "kagent-ryzen.tail286401.ts.net";
      icon = iconPath "kagent.svg";
      description = "Kagent Kubernetes AI agent framework";
      categories = "Development;Network;System;";
      keywords = "kagent;kubernetes;ai;agent;llm;automation;";
      scope = "https://kagent-ryzen.tail286401.ts.net/";
      ulid = "01MEQFVGM6Q5T9V4W7Y1Z3A2B8";  # Generated 2025-11-18
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 75;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "kagent-ryzen.tail286401.ts.net" ];
    }

    # Agent Gateway (Ryzen K8s via Tailscale)
    {
      name = "Agent Gateway";
      url = "https://agentgateway-ryzen.tail286401.ts.net";
      domain = "agentgateway-ryzen.tail286401.ts.net";
      icon = iconPath "agent-gateway.svg";
      description = "Agent Gateway API gateway for AI agents";
      categories = "Development;Network;System;";
      keywords = "agent;gateway;api;kubernetes;ai;routing;";
      scope = "https://agentgateway-ryzen.tail286401.ts.net/";
      ulid = "01MEQFVKN7R6V0W5X8Z2A4B3C9";  # Generated 2025-11-18
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 76;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "agentgateway-ryzen.tail286401.ts.net" ];
    }

    # ============================================
    # Kubernetes PWAs (Ryzen via Tailscale)
    # ============================================

    # Grafana (Ryzen K8s via Tailscale)
    {
      name = "Grafana Local";
      url = "https://grafana-ryzen.tail286401.ts.net";
      domain = "grafana-ryzen.tail286401.ts.net";
      icon = iconPath "grafana.svg";
      description = "Grafana observability dashboard for CNOE local";
      categories = "Network;Development;";
      keywords = "grafana;observability;metrics;logs;kubernetes;cnoe;";
      scope = "https://grafana-ryzen.tail286401.ts.net/";
      ulid = "01JGNK2P3Q4R5S6T7V8W9X0Y1Z";  # Generated 2026-01-01
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 95;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "grafana-ryzen.tail286401.ts.net" ];
    }

    # Langfuse (Ryzen K8s via Tailscale)
    {
      name = "Langfuse";
      url = "https://langfuse-ryzen.tail286401.ts.net";
      domain = "langfuse-ryzen.tail286401.ts.net";
      icon = iconPath "langfuse.svg";
      description = "Langfuse AI observability platform";
      categories = "Network;Development;";
      keywords = "langfuse;ai;observability;tracing;kubernetes;";
      scope = "https://langfuse-ryzen.tail286401.ts.net/";
      ulid = "4NAWESCFFZM8CHZJBCMXVWF4TK";  # Generated 2025-12-24
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 84;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "langfuse-ryzen.tail286401.ts.net" ];
    }

    # Jaeger (Ryzen K8s via Tailscale)
    {
      name = "Jaeger";
      url = "https://jaeger-ryzen.tail286401.ts.net";
      domain = "jaeger-ryzen.tail286401.ts.net";
      icon = iconPath "jaeger.svg";
      description = "Jaeger distributed tracing platform";
      categories = "Network;Development;";
      keywords = "jaeger;tracing;observability;distributed;kubernetes;";
      scope = "https://jaeger-ryzen.tail286401.ts.net/";
      ulid = "01JGNH8K2M3P4Q5R6S7T8V9W0X";  # Generated 2025-12-30
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 93;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "jaeger-ryzen.tail286401.ts.net" ];
    }

    # Flipt (Ryzen K8s via Tailscale)
    {
      name = "Flipt";
      url = "https://flipt-ryzen.tail286401.ts.net";
      domain = "flipt-ryzen.tail286401.ts.net";
      icon = iconPath "flipt.svg";
      description = "Flipt feature flag management platform";
      categories = "Development;Network;";
      keywords = "flipt;feature-flags;toggles;experimentation;kubernetes;";
      scope = "https://flipt-ryzen.tail286401.ts.net/";
      ulid = "01KDPH3T12J6EQ2N6SZRGW1VPD";  # Generated 2025-12-29
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 92;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "flipt-ryzen.tail286401.ts.net" ];
    }

    # RAG WebUI (Ryzen K8s via Tailscale)
    {
      name = "RAG WebUI";
      url = "https://rag-webui-ryzen.tail286401.ts.net";
      domain = "rag-webui-ryzen.tail286401.ts.net";
      icon = iconPath "rag-webui.svg";
      description = "CAIPE RAG WebUI - AI-powered knowledge retrieval interface";
      categories = "Development;Network;";
      keywords = "rag;webui;caipe;ai;llm;retrieval;knowledge;cnoe;";
      scope = "https://rag-webui-ryzen.tail286401.ts.net/";
      ulid = "01KDPH3T1CD7ECNDJPQ01VFH40";  # Generated 2025-12-29
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 94;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "rag-webui-ryzen.tail286401.ts.net" ];
    }

    # NocoDB (Ryzen K8s via Tailscale)
    {
      name = "NocoDB";
      url = "https://nocodb-ryzen.tail286401.ts.net";
      domain = "nocodb-ryzen.tail286401.ts.net";
      icon = iconPath "nocodb.svg";
      description = "NocoDB - Open source Airtable alternative";
      categories = "Development;Network;Office;";
      keywords = "nocodb;database;airtable;spreadsheet;no-code;kubernetes;";
      scope = "https://nocodb-ryzen.tail286401.ts.net/";
      ulid = "7WK88MM2SQ3M161Q045W2R50HK";  # Generated 2026-01-04
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 96;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "nocodb-ryzen.tail286401.ts.net" ];
    }

    # Oracle Cloud Console
    {
      name = "Oracle Cloud";
      url = "https://cloud.oracle.com";
      domain = "cloud.oracle.com";
      icon = iconPath "oracle-cloud.svg";
      description = "Oracle Cloud Infrastructure management console";
      categories = "Network;Development;System;";
      keywords = "oracle;cloud;oci;infrastructure;server;hosting;devops;";
      scope = "https://cloud.oracle.com/";
      ulid = "WVSN1BT353D2TCM3F9BR9H6BVR";  # Generated 2026-01-04
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 97;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "cloud.oracle.com" "console.oracle.com" ];
      # Feature 118: Oracle auth domains
      auth_domains = [ "login.oracle.com" "idcs.oracle.com" ];
    }

    # Cachix
    {
      name = "Cachix";
      url = "https://app.cachix.org";
      domain = "app.cachix.org";
      icon = iconPath "cachix.svg";
      description = "Cachix - Nix binary cache hosting service";
      categories = "Development;Network;";
      keywords = "cachix;nix;cache;binary;ci;devops;";
      scope = "https://app.cachix.org/";
      ulid = "3NZ43C737HVW0NAHKEWD66FSDA";  # Generated 2026-01-06
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 98;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "app.cachix.org" "cachix.org" "www.cachix.org" ];
    }

    # Hercules CI
    {
      name = "Hercules CI";
      url = "https://hercules-ci.com";
      domain = "hercules-ci.com";
      icon = iconPath "hercules-ci.png";
      description = "Hercules CI - Nix-native CI/CD platform";
      categories = "Development;Network;";
      keywords = "hercules;ci;cd;nix;devops;continuous-integration;";
      scope = "https://hercules-ci.com/";
      ulid = "4QNRHPAS95TCX1XETP8EBGG97Y";  # Generated 2026-01-06
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 99;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "hercules-ci.com" "www.hercules-ci.com" ];
    }

    # Dapr Dashboard (Ryzen K8s via Tailscale)
    {
      name = "Dapr Dashboard";
      url = "https://dapr-ryzen.tail286401.ts.net";
      domain = "dapr-ryzen.tail286401.ts.net";
      icon = iconPath "dapr.svg";
      description = "Dapr - Distributed application runtime dashboard";
      categories = "Development;Network;";
      keywords = "dapr;microservices;kubernetes;sidecar;distributed;runtime;";
      scope = "https://dapr-ryzen.tail286401.ts.net/";
      ulid = "01KEAAZKYV8GMQGH5YX6ZV4GS5";  # Generated 2026-01-06
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 100;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "dapr-ryzen.tail286401.ts.net" ];
    }

    # Attu (Ryzen K8s via Tailscale)
    {
      name = "Attu";
      url = "https://attu-ryzen.tail286401.ts.net";
      domain = "attu-ryzen.tail286401.ts.net";
      icon = iconPath "milvus.svg";
      description = "Attu - Milvus vector database administration UI";
      categories = "Development;Network;";
      keywords = "attu;milvus;vector;database;admin;kubernetes;";
      scope = "https://attu-ryzen.tail286401.ts.net/";
      ulid = "03AYXQ8S24G2ZFWBJ54G83A4F7";  # Generated 2026-01-12
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 101;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "attu-ryzen.tail286401.ts.net" ];
    }

    # Crawl4AI (Ryzen K8s via Tailscale)
    {
      name = "Crawl4AI";
      url = "https://crawl4ai-ryzen.tail286401.ts.net";
      domain = "crawl4ai-ryzen.tail286401.ts.net";
      icon = iconPath "crawl4ai.svg";
      description = "Crawl4AI - Open-source LLM-friendly web crawler";
      categories = "Development;Network;";
      keywords = "crawl4ai;crawler;scraper;llm;ai;web;kubernetes;";
      scope = "https://crawl4ai-ryzen.tail286401.ts.net/";
      ulid = "61ZKKF8QQHC7XYGFCWGMWY85CV";  # Generated 2026-01-12
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 102;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "crawl4ai-ryzen.tail286401.ts.net" ];
    }

    # AI Chatbot (Ryzen K8s via Tailscale)
    {
      name = "AI Chatbot";
      url = "https://ai-chatbot-ryzen.tail286401.ts.net";
      domain = "ai-chatbot-ryzen.tail286401.ts.net";
      icon = iconPath "nextjs.svg";
      description = "Vercel AI SDK Chatbot - Next.js AI chat template";
      categories = "Development;Network;";
      keywords = "ai;chatbot;vercel;nextjs;llm;chat;kubernetes;";
      scope = "https://ai-chatbot-ryzen.tail286401.ts.net/";
      ulid = "6EBKR8NA2A8TMS02SJ7NSR77RG";  # Generated 2026-01-12
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 103;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "ai-chatbot-ryzen.tail286401.ts.net" ];
    }

    # Open SWE (Ryzen K8s via Tailscale)
    {
      name = "Open SWE";
      url = "https://open-swe-ui-ryzen.tail286401.ts.net";
      domain = "open-swe-ui-ryzen.tail286401.ts.net";
      icon = iconPath "open-swe.png";
      description = "Open SWE - LangChain-based asynchronous coding agent";
      categories = "Development;Network;";
      keywords = "open-swe;langchain;langgraph;agent;ai;coding;kubernetes;";
      scope = "https://open-swe-ui-ryzen.tail286401.ts.net/";
      ulid = "5PCVTAVZTD0F050E23VXNXP7TK";  # Generated 2026-01-13
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 104;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "open-swe-ui-ryzen.tail286401.ts.net" ];
    }

    # Open WebUI (Ryzen K8s via Tailscale)
    {
      name = "Open WebUI";
      url = "https://openwebui-ryzen.tail286401.ts.net";
      domain = "openwebui-ryzen.tail286401.ts.net";
      icon = iconPath "openwebui.svg";
      description = "Open WebUI - Open source LLM user interface";
      categories = "Development;Network;";
      keywords = "openwebui;llm;ollama;chat;ai;interface;kubernetes;";
      scope = "https://openwebui-ryzen.tail286401.ts.net/";
      ulid = "6M403VYCD36S0E6R0PTD2ZYA5M";  # Generated 2026-01-13
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 105;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "openwebui-ryzen.tail286401.ts.net" ];
    }

    # Phoenix Azire (Ryzen K8s via Tailscale)
    {
      name = "Phoenix Azire";
      url = "https://phoenix-ryzen.tail286401.ts.net";
      domain = "phoenix-ryzen.tail286401.ts.net";
      icon = iconPath "phoenix-azire.svg";
      description = "Phoenix Azire - AI observability and LLM tracing platform";
      categories = "Development;Network;";
      keywords = "phoenix;azire;ai;observability;tracing;llm;kubernetes;";
      scope = "https://phoenix-ryzen.tail286401.ts.net/";
      ulid = "5A70F22AX1NP456PSAFESPEZ5E";  # Generated 2026-01-26
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 106;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "phoenix-ryzen.tail286401.ts.net" ];
    }

    # AI Workflow Builder (Ryzen K8s via Tailscale)
    {
      name = "AI Workflow Builder";
      url = "https://workflow-builder-ryzen.tail286401.ts.net";
      domain = "workflow-builder-ryzen.tail286401.ts.net";
      icon = iconPath "ai-workflow-builder.svg";
      description = "AI Workflow Builder - Visual node-based workflow automation editor";
      categories = "Development;Network;";
      keywords = "workflow;builder;visual;editor;automation;ai;nodes;react-flow;nextjs;";
      scope = "https://workflow-builder-ryzen.tail286401.ts.net/";
      ulid = "31EYAA8SZG1WY6TCVYB2PJDNBM";  # Generated 2026-01-29
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 108;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "workflow-builder-ryzen.tail286401.ts.net" ];
    }

    # Redis Insights (Ryzen K8s via Tailscale)
    {
      name = "Redis Insights";
      url = "https://redisinsight-ryzen.tail286401.ts.net";
      domain = "redisinsight-ryzen.tail286401.ts.net";
      icon = iconPath "redis-insights.svg";
      description = "Redis Insights - Redis database management and visualization tool";
      categories = "Development;Network;";
      keywords = "redis;insights;database;cache;visualization;kubernetes;cnoe;";
      scope = "https://redisinsight-ryzen.tail286401.ts.net/";
      ulid = "348E7WKJSMP0YRHTHEY3ETR5J6";  # Generated 2026-02-02
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 109;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "redisinsight-ryzen.tail286401.ts.net" ];
    }

    # Dify (Ryzen K8s via Tailscale)
    {
      name = "Dify";
      url = "https://dify-ryzen.tail286401.ts.net";
      domain = "dify-ryzen.tail286401.ts.net";
      icon = iconPath "dify.svg";
      description = "Dify - Open-source LLM app development platform and AI workflow builder";
      categories = "Development;Network;";
      keywords = "dify;ai;llm;workflow;builder;chatbot;agent;kubernetes;cnoe;";
      scope = "https://dify-ryzen.tail286401.ts.net/";
      ulid = "53SPYVASDFAZCB0X58DZZS29Y4";  # Generated 2026-02-03
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 110;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "dify-ryzen.tail286401.ts.net" ];
    }

    # JupyterHub (Ryzen K8s via Tailscale)
    {
      name = "JupyterHub";
      url = "https://jupyterhub-ryzen.tail286401.ts.net";
      domain = "jupyterhub-ryzen.tail286401.ts.net";
      icon = iconPath "jupyterhub.svg";
      description = "JupyterHub - Multi-user Jupyter notebook server";
      categories = "Development;Network;Education;";
      keywords = "jupyter;jupyterhub;notebook;python;data-science;kubernetes;cnoe;";
      scope = "https://jupyterhub-ryzen.tail286401.ts.net/";
      ulid = "1JJBSGAS1QBR1875WQ1NARB1YK";  # Generated 2026-02-03
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 111;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "jupyterhub-ryzen.tail286401.ts.net" ];
    }

    # KubeVela (Ryzen K8s via Tailscale)
    {
      name = "KubeVela";
      url = "https://velaux-ryzen.tail286401.ts.net";
      domain = "velaux-ryzen.tail286401.ts.net";
      icon = iconPath "kubevela.svg";
      description = "KubeVela - Modern application delivery platform";
      categories = "Development;Network;Utility;";
      keywords = "kubevela;vela;velaux;kubernetes;k8s;deployment;oam;application;cnoe;";
      scope = "https://velaux-ryzen.tail286401.ts.net/";
      ulid = "3037TSQ2W3RH3M7PRDBXFCT2K0";  # Generated 2026-02-04
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 112;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "velaux-ryzen.tail286401.ts.net" ];
    }

    # Activepieces (Ryzen K8s via Tailscale)
    {
      name = "Activepieces";
      url = "https://activepieces-ryzen.tail286401.ts.net";
      domain = "activepieces-ryzen.tail286401.ts.net";
      icon = iconPath "activepieces.svg";
      description = "Activepieces - Open source workflow automation platform";
      categories = "Development;Network;";
      keywords = "activepieces;automation;workflow;zapier;n8n;integrations;kubernetes;cnoe;";
      scope = "https://activepieces-ryzen.tail286401.ts.net/";
      ulid = "7BW50E7SR9479J379C01JDP0Y6";  # Generated 2026-02-04
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 113;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "activepieces-ryzen.tail286401.ts.net" ];
    }

    # MCP Inspector (Ryzen K8s via Tailscale)
    {
      name = "MCP Inspector";
      url = "https://mcp-inspector-ryzen.tail286401.ts.net/?MCP_PROXY_PORT=8443";
      domain = "mcp-inspector-ryzen.tail286401.ts.net";
      icon = iconPath "mcp-inspector.svg";
      description = "MCP Inspector - Visual testing and debugging tool for MCP servers";
      categories = "Development;Network;";
      keywords = "mcp;inspector;model;context;protocol;debug;test;server;ai;";
      scope = "https://mcp-inspector-ryzen.tail286401.ts.net/";
      ulid = "39ADZC4WY3Y4AKR1YVSZDR1NKQ";  # Generated 2026-02-11
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 114;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "mcp-inspector-ryzen.tail286401.ts.net" ];
    }

    # LibreChat (local)
    {
      name = "LibreChat";
      url = "http://localhost:3080";
      domain = "localhost";
      icon = iconPath "librechat.svg";
      description = "LibreChat - Open-source AI chat platform";
      categories = "Development;Network;";
      keywords = "librechat;ai;chat;llm;openai;anthropic;local;";
      scope = "http://localhost:3080/";
      ulid = "4VRKDPN8WG2M5T7X9Q1BJ3F6YH";  # Generated 2026-02-13
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 116;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing - localhost is too generic
      routing_domains = [ ];  # Disabled - localhost:3080 would conflict with other local services
    }

    # Flowise (Ryzen K8s via Tailscale)
    {
      name = "Flowise";
      url = "https://flowise-ryzen.tail286401.ts.net";
      domain = "flowise-ryzen.tail286401.ts.net";
      icon = "/etc/nixos/assets/icons/flowise.svg";
      description = "Flowise - Build AI Agents, Visually";
      categories = "Development;Network;";
      keywords = "flowise;ai;agent;flow;langchain;llm;chatbot;workflow;";
      scope = "https://flowise-ryzen.tail286401.ts.net/";
      ulid = "36G226WSWG11H0T2ACVZ6FZXCN";  # Generated 2026-02-12
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 115;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "flowise-ryzen.tail286401.ts.net" ];
    }

    # Mastra Playground (Ryzen K8s via Tailscale)
    {
      name = "Mastra Playground";
      url = "https://mastra-playground-ryzen.tail286401.ts.net/";
      domain = "mastra-playground-ryzen.tail286401.ts.net";
      icon = "/etc/nixos/assets/icons/mastra-playground.svg";
      description = "Mastra Playground - AI agent framework testing environment";
      categories = "Development;Network;";
      keywords = "mastra;ai;agent;playground;typescript;framework;llm;";
      scope = "https://mastra-playground-ryzen.tail286401.ts.net/";
      ulid = "34C8ASD2334ZVN4KP7JX1TJHPH";  # Generated 2026-02-14
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 78;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "mastra-playground-ryzen.tail286401.ts.net" ];
    }
  ];

  # Filter and format sites
  filteredSites = builtins.filter shouldInclude allPwaSites;
  pwaSites = builtins.map (pwa: pwa // { name = formatName pwa; }) filteredSites;

in
{
  inherit pwaSites;

  # ULID validation function
  # ULID format: 26 characters from alphabet [0-9A-HJKMNP-TV-Z] (excludes I, L, O, U)
  validateULID = ulid:
    let
      len = builtins.stringLength ulid;
      # Check if string contains only valid ULID characters
      isValidChars = builtins.match "[0-9A-HJKMNP-TV-Z]*" ulid != null;
    in
    len == 26 && isValidChars;

  # Helper to check for duplicate ULIDs
  checkDuplicateULIDs = pwas:
    let
      ulids = builtins.map (pwa: pwa.ulid) pwas;
      uniqueULIDs = lib.lists.unique ulids;
    in
    if builtins.length ulids != builtins.length uniqueULIDs
    then throw "Duplicate ULIDs detected in pwa-sites.nix"
    else true;

  # Additional trusted domains for Firefox policies
  # These are domains that need clipboard/tracking exception but aren't PWAs
  additionalTrustedDomains = [
    # GitHub ecosystem
    "github.dev"
    "codespaces.githubusercontent.com"

    # AI tools (not all are PWAs)
    "chatgpt.com"

    # Authentication
    "my.1password.com"
    "1password.com"
  ];

  # Helper functions to extract domain patterns for Firefox policies
  helpers = {
    # Extract unique base domains from PWA sites
    # Returns list like: ["google.com", "youtube.com", "github.com", ...]
    getBaseDomains = sites: lib.unique (builtins.map (site: site.domain) sites);

    # Generate Firefox policy exception patterns
    # Returns list like: ["https://google.com", "https://*.google.com", ...]
    getDomainPatterns = sites: additionalDomains:
      let
        pwaDomains = lib.unique (builtins.map (site: site.domain) sites);
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
        lib.flatten (builtins.map generatePatterns allDomains);
  };
}
