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

    # Keycloak (CNOE local)
    {
      name = "Keycloak";
      url = "https://keycloak.cnoe.localtest.me:8443";
      domain = "keycloak.cnoe.localtest.me";
      icon = iconPath "keycloak.svg";
      description = "Keycloak identity and access management";
      categories = "Security;Network;";
      keywords = "keycloak;iam;auth;openid;single-sign-on;kubernetes;";
      scope = "https://keycloak.cnoe.localtest.me:8443/";
      ulid = "01MD4CZ7H4KJ4TR0C2Q3C8ZQ9V";  # Generated 2025-11-17
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 68;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "keycloak.cnoe.localtest.me" ];
    }

    # Backstage (CNOE local)
    {
      name = "Backstage";
      url = "https://backstage.cnoe.localtest.me:8443";
      domain = "backstage.cnoe.localtest.me";
      icon = iconPath "backstage.svg";
      description = "Backstage developer portal";
      categories = "Development;Network;";
      keywords = "backstage;developer-portal;sdp;platform;kubernetes;";
      scope = "https://backstage.cnoe.localtest.me:8443/";
      ulid = "01MD4D0A6S2CVXKNNY4EJ5PQ1G";  # Generated 2025-11-17
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 69;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "backstage.cnoe.localtest.me" ];
    }

    # ArgoCD (CNOE local)
    {
      name = "ArgoCD";
      url = "https://argocd.cnoe.localtest.me:8443";
      domain = "argocd.cnoe.localtest.me";
      icon = iconPath "argocd.svg";
      description = "ArgoCD GitOps controller";
      categories = "Development;Network;System;";
      keywords = "argocd;gitops;cd;kubernetes;devops;";
      scope = "https://argocd.cnoe.localtest.me:8443/";
      ulid = "01MD4D0N7A8F9P6QS0R1TV2WX3";  # Generated 2025-11-17
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 70;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "argocd.cnoe.localtest.me" ];
    }

    # Argo Workflows (CNOE local)
    {
      name = "Argo Workflows";
      url = "https://argo-workflows.cnoe.localtest.me:8443";
      domain = "argo-workflows.cnoe.localtest.me";
      icon = iconPath "argo-workflows.png";
      description = "Argo Workflows - Kubernetes-native workflow engine";
      categories = "Development;Network;System;";
      keywords = "argo;workflows;kubernetes;pipelines;ci;automation;";
      scope = "https://argo-workflows.cnoe.localtest.me:8443/";
      ulid = "56RN5CMB8EJQ8KEVPWDR2GB7PX";  # Generated 2025-01-29
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 107;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "argo-workflows.cnoe.localtest.me" ];
    }

    # ArgoCD (Talos/ai401kchat)
    {
      name = "ArgoCD Talos";
      url = "https://argocd.ai401kchat.com";
      domain = "argocd.ai401kchat.com";
      icon = iconPath "argocd-talos.svg";
      description = "ArgoCD GitOps controller for Talos Kubernetes cluster";
      categories = "Development;Network;System;";
      keywords = "argocd;gitops;cd;kubernetes;devops;talos;ai401kchat;";
      scope = "https://argocd.ai401kchat.com/";
      ulid = "3YBB66K55HEZRW2GC25M8W53NJ";  # Generated 2025-12-09
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 77;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "argocd.ai401kchat.com" ];
    }

    # Gitea (CNOE local)
    {
      name = "Gitea";
      url = "https://gitea.cnoe.localtest.me:8443";
      domain = "gitea.cnoe.localtest.me";
      icon = iconPath "gitea.svg";
      description = "Gitea self-hosted git service";
      categories = "Development;Network;";
      keywords = "gitea;git;scm;code;devops;kubernetes;";
      scope = "https://gitea.cnoe.localtest.me:8443/";
      ulid = "01MD4D14BDS6Z4GMY3K9HFT8PA";  # Generated 2025-11-17
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 71;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "gitea.cnoe.localtest.me" ];
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

    # Kargo (CNOE local)
    {
      name = "Kargo";
      url = "https://kargo.cnoe.localtest.me:8443";
      domain = "kargo.cnoe.localtest.me";
      icon = iconPath "kargo.png";
      description = "Kargo continuous delivery and promotion engine for Kubernetes";
      categories = "Development;Network;System;";
      keywords = "kargo;kubernetes;cd;gitops;promotion;delivery;";
      scope = "https://kargo.cnoe.localtest.me:8443/";
      ulid = "01MEQFV8K4N3R7S2T5W9X0Y1Z6";  # Generated 2025-11-18
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 73;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "kargo.cnoe.localtest.me" ];
    }

    # Headlamp (CNOE local)
    {
      name = "Headlamp";
      url = "https://headlamp.cnoe.localtest.me:8443";
      domain = "headlamp.cnoe.localtest.me";
      icon = iconPath "headlamp.svg";
      description = "Headlamp Kubernetes dashboard";
      categories = "Development;Network;System;";
      keywords = "headlamp;kubernetes;dashboard;k8s;cluster;";
      scope = "https://headlamp.cnoe.localtest.me:8443/";
      ulid = "01MEQFVCK5P4S8T3V6X0Y2Z7A1";  # Generated 2025-11-18
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 74;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "headlamp.cnoe.localtest.me" ];
    }

    # Kagent (CNOE local)
    {
      name = "Kagent";
      url = "https://kagent.cnoe.localtest.me:8443";
      domain = "kagent.cnoe.localtest.me";
      icon = iconPath "kagent.svg";
      description = "Kagent Kubernetes AI agent framework";
      categories = "Development;Network;System;";
      keywords = "kagent;kubernetes;ai;agent;llm;automation;";
      scope = "https://kagent.cnoe.localtest.me:8443/";
      ulid = "01MEQFVGM6Q5T9V4W7Y1Z3A2B8";  # Generated 2025-11-18
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 75;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "kagent.cnoe.localtest.me" ];
    }

    # Agent Gateway (CNOE local)
    {
      name = "Agent Gateway";
      url = "https://agentgateway.cnoe.localtest.me:8443";
      domain = "agentgateway.cnoe.localtest.me";
      icon = iconPath "agent-gateway.svg";
      description = "Agent Gateway API gateway for AI agents";
      categories = "Development;Network;System;";
      keywords = "agent;gateway;api;kubernetes;ai;routing;";
      scope = "https://agentgateway.cnoe.localtest.me:8443/";
      ulid = "01MEQFVKN7R6V0W5X8Z2A4B3C9";  # Generated 2025-11-18
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 76;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "agentgateway.cnoe.localtest.me" ];
    }

    # ============================================
    # Talos Cluster PWAs (ai401kchat.com)
    # Purple-themed icons to distinguish from Tailscale variants
    # ============================================

    # Kargo (Talos/ai401kchat)
    {
      name = "Kargo Talos";
      url = "https://kargo.ai401kchat.com";
      domain = "kargo.ai401kchat.com";
      icon = iconPath "kargo.png";  # Using same PNG (no SVG available)
      description = "Kargo continuous delivery and promotion engine for Talos cluster";
      categories = "Development;Network;System;";
      keywords = "kargo;kubernetes;cd;gitops;promotion;delivery;talos;ai401kchat;";
      scope = "https://kargo.ai401kchat.com/";
      ulid = "45XFC05KF4YM4GK9SMKW8S4EPZ";  # Generated 2025-12-09
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 79;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "kargo.ai401kchat.com" ];
    }

    # Headlamp (Talos/ai401kchat)
    {
      name = "Headlamp Talos";
      url = "https://headlamp.ai401kchat.com";
      domain = "headlamp.ai401kchat.com";
      icon = iconPath "headlamp-talos.svg";
      description = "Headlamp Kubernetes dashboard for Talos cluster";
      categories = "Development;Network;System;";
      keywords = "headlamp;kubernetes;dashboard;k8s;cluster;talos;ai401kchat;";
      scope = "https://headlamp.ai401kchat.com/";
      ulid = "7Q27F97E9F496X7ZQ47ANH88CP";  # Generated 2025-12-09
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 80;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "headlamp.ai401kchat.com" ];
    }

    # Gitea (Talos/ai401kchat)
    {
      name = "Gitea Talos";
      url = "https://gitea.ai401kchat.com";
      domain = "gitea.ai401kchat.com";
      icon = iconPath "gitea-talos.svg";
      description = "Gitea self-hosted git service for Talos cluster";
      categories = "Development;Network;";
      keywords = "gitea;git;scm;code;devops;kubernetes;talos;ai401kchat;";
      scope = "https://gitea.ai401kchat.com/";
      ulid = "72TGWGVAMBGEA9T1M4MS75S8PG";  # Generated 2025-12-09
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 81;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "gitea.ai401kchat.com" ];
    }

    # Keycloak (Talos/ai401kchat)
    {
      name = "Keycloak Talos";
      url = "https://keycloak.ai401kchat.com";
      domain = "keycloak.ai401kchat.com";
      icon = iconPath "keycloak-talos.svg";
      description = "Keycloak identity and access management for Talos cluster";
      categories = "Security;Network;";
      keywords = "keycloak;iam;auth;openid;single-sign-on;kubernetes;talos;ai401kchat;";
      scope = "https://keycloak.ai401kchat.com/";
      ulid = "514S283M0EGKNVDMYKAR3635H6";  # Generated 2025-12-09
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 82;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "keycloak.ai401kchat.com" ];
    }

    # ============================================
    # Observability Stack PWAs (Hub Cluster)
    # ============================================

    # Grafana Hub
    {
      name = "Grafana Hub";
      host = "hub";
      url = "https://grafana-hub.tail286401.ts.net";
      domain = "grafana-hub.tail286401.ts.net";
      icon = iconPath "grafana.svg";
      description = "Grafana dashboard for Hub cluster";
      categories = "Network;Development;";
      keywords = "grafana;observability;metrics;logs;hub;";
      scope = "https://grafana-hub.tail286401.ts.net/";
      ulid = "6F5SBQ6RZQPTASDHNFNERW976H";  # Generated 2025-12-24
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 83;
      preferred_monitor_role = "secondary";
    }

    # Grafana (CNOE local)
    {
      name = "Grafana Local";
      url = "https://grafana.cnoe.localtest.me:8443";
      domain = "grafana.cnoe.localtest.me";
      icon = iconPath "grafana.svg";
      description = "Grafana observability dashboard for CNOE local";
      categories = "Network;Development;";
      keywords = "grafana;observability;metrics;logs;kubernetes;cnoe;";
      scope = "https://grafana.cnoe.localtest.me:8443/";
      ulid = "01JGNK2P3Q4R5S6T7V8W9X0Y1Z";  # Generated 2026-01-01
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 95;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "grafana.cnoe.localtest.me" ];
    }

    # Langfuse (CNOE local)
    {
      name = "Langfuse";
      url = "https://langfuse.cnoe.localtest.me:8443";
      domain = "langfuse.cnoe.localtest.me";
      icon = iconPath "langfuse.svg";
      description = "Langfuse AI observability platform";
      categories = "Network;Development;";
      keywords = "langfuse;ai;observability;tracing;kubernetes;";
      scope = "https://langfuse.cnoe.localtest.me:8443/";
      ulid = "4NAWESCFFZM8CHZJBCMXVWF4TK";  # Generated 2025-12-24
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 84;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "langfuse.cnoe.localtest.me" ];
    }

    # Jaeger (CNOE local)
    {
      name = "Jaeger";
      url = "https://jaeger.cnoe.localtest.me:8443";
      domain = "jaeger.cnoe.localtest.me";
      icon = iconPath "jaeger.svg";
      description = "Jaeger distributed tracing platform";
      categories = "Network;Development;";
      keywords = "jaeger;tracing;observability;distributed;kubernetes;";
      scope = "https://jaeger.cnoe.localtest.me:8443/";
      ulid = "01JGNH8K2M3P4Q5R6S7T8V9W0X";  # Generated 2025-12-30
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 93;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "jaeger.cnoe.localtest.me" ];
    }

    # Alloy Hub
    {
      name = "Alloy Hub";
      host = "hub";
      url = "https://alloy-hub.tail286401.ts.net";
      domain = "alloy-hub.tail286401.ts.net";
      icon = iconPath "alloy.svg";
      description = "Grafana Alloy debug UI for Hub cluster";
      categories = "Network;Development;";
      keywords = "alloy;grafana;collector;telemetry;hub;";
      scope = "https://alloy-hub.tail286401.ts.net/";
      ulid = "0YF8REBN1HG7BF9W7N2TJGC4JA";  # Generated 2025-12-24
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 85;
      preferred_monitor_role = "secondary";
    }

    # ============================================
    # Observability Stack PWAs (ThinkPad Cluster)
    # ============================================

    # Grafana ThinkPad
    {
      name = "Grafana ThinkPad";
      host = "thinkpad";
      url = "https://grafana-thinkpad.tail286401.ts.net";
      domain = "grafana-thinkpad.tail286401.ts.net";
      icon = iconPath "grafana.svg";
      description = "Grafana dashboard for ThinkPad cluster";
      categories = "Network;Development;";
      keywords = "grafana;observability;metrics;logs;thinkpad;";
      scope = "https://grafana-thinkpad.tail286401.ts.net/";
      ulid = "7P1BD85PQGTZA9QHS5RAK2T1N6";  # Generated 2025-12-24
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 86;
      preferred_monitor_role = "secondary";
    }


    # Alloy ThinkPad
    {
      name = "Alloy ThinkPad";
      host = "thinkpad";
      url = "http://localhost:12345";
      domain = "localhost";
      icon = iconPath "alloy.svg";
      description = "Grafana Alloy debug UI for ThinkPad cluster";
      categories = "Network;Development;";
      keywords = "alloy;grafana;collector;telemetry;thinkpad;";
      scope = "http://localhost:12345/";
      ulid = "3Q6FKYJZE0584G3Q2HW6SCRS5G";  # Generated 2025-12-24
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 88;
      preferred_monitor_role = "secondary";
    }

    # ============================================
    # Observability Stack PWAs (Ryzen Cluster)
    # ============================================

    # Grafana Ryzen
    {
      name = "Grafana Ryzen";
      host = "ryzen";
      url = "https://grafana-ryzen.tail286401.ts.net";
      domain = "grafana-ryzen.tail286401.ts.net";
      icon = iconPath "grafana.svg";
      description = "Grafana dashboard for Ryzen cluster";
      categories = "Network;Development;";
      keywords = "grafana;observability;metrics;logs;ryzen;";
      scope = "https://grafana-ryzen.tail286401.ts.net/";
      ulid = "4GYTVH57ZRH7ZTBZQZZ5G6XAJX";  # Generated 2025-12-24
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 89;
      preferred_monitor_role = "secondary";
    }


    # Alloy Ryzen
    {
      name = "Alloy Ryzen";
      host = "ryzen";
      url = "http://localhost:12345";
      domain = "localhost";
      icon = iconPath "alloy.svg";
      description = "Grafana Alloy debug UI for Ryzen cluster";
      categories = "Network;Development;";
      keywords = "alloy;grafana;collector;telemetry;ryzen;";
      scope = "http://localhost:12345/";
      ulid = "4ZY96QS21XXYC2MY9PMPECBE7M";  # Generated 2025-12-24
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 91;
      preferred_monitor_role = "secondary";
    }

    # ============================================
    # CNOE/CAIPE PWAs (localtest.me)
    # ============================================

    # Flipt (CNOE local)
    {
      name = "Flipt";
      url = "https://flipt.cnoe.localtest.me:8443";
      domain = "flipt.cnoe.localtest.me";
      icon = iconPath "flipt.svg";
      description = "Flipt feature flag management platform";
      categories = "Development;Network;";
      keywords = "flipt;feature-flags;toggles;experimentation;kubernetes;";
      scope = "https://flipt.cnoe.localtest.me:8443/";
      ulid = "01KDPH3T12J6EQ2N6SZRGW1VPD";  # Generated 2025-12-29
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 92;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "flipt.cnoe.localtest.me" ];
    }

    # RAG WebUI (CNOE/CAIPE local)
    {
      name = "RAG WebUI";
      url = "https://rag-webui.cnoe.localtest.me:8443";
      domain = "rag-webui.cnoe.localtest.me";
      icon = iconPath "rag-webui.svg";
      description = "CAIPE RAG WebUI - AI-powered knowledge retrieval interface";
      categories = "Development;Network;";
      keywords = "rag;webui;caipe;ai;llm;retrieval;knowledge;cnoe;";
      scope = "https://rag-webui.cnoe.localtest.me:8443/";
      ulid = "01KDPH3T1CD7ECNDJPQ01VFH40";  # Generated 2025-12-29
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 94;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "rag-webui.cnoe.localtest.me" ];
    }

    # NocoDB (CNOE local)
    {
      name = "NocoDB";
      url = "https://nocodb.cnoe.localtest.me:8443";
      domain = "nocodb.cnoe.localtest.me";
      icon = iconPath "nocodb.svg";
      description = "NocoDB - Open source Airtable alternative";
      categories = "Development;Network;Office;";
      keywords = "nocodb;database;airtable;spreadsheet;no-code;kubernetes;";
      scope = "https://nocodb.cnoe.localtest.me:8443/";
      ulid = "7WK88MM2SQ3M161Q045W2R50HK";  # Generated 2026-01-04
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 96;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "nocodb.cnoe.localtest.me" ];
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

    # Dapr Dashboard
    {
      name = "Dapr Dashboard";
      url = "https://dapr.cnoe.localtest.me:8443";
      domain = "dapr.cnoe.localtest.me";
      icon = iconPath "dapr.svg";
      description = "Dapr - Distributed application runtime dashboard";
      categories = "Development;Network;";
      keywords = "dapr;microservices;kubernetes;sidecar;distributed;runtime;";
      scope = "https://dapr.cnoe.localtest.me:8443/";
      ulid = "01KEAAZKYV8GMQGH5YX6ZV4GS5";  # Generated 2026-01-06
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 100;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "dapr.cnoe.localtest.me" ];
    }

    # Attu (Milvus vector database UI)
    {
      name = "Attu";
      url = "https://attu.cnoe.localtest.me:8443";
      domain = "attu.cnoe.localtest.me";
      icon = iconPath "milvus.svg";
      description = "Attu - Milvus vector database administration UI";
      categories = "Development;Network;";
      keywords = "attu;milvus;vector;database;admin;kubernetes;";
      scope = "https://attu.cnoe.localtest.me:8443/";
      ulid = "03AYXQ8S24G2ZFWBJ54G83A4F7";  # Generated 2026-01-12
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 101;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "attu.cnoe.localtest.me" ];
    }

    # Crawl4AI (CNOE local)
    {
      name = "Crawl4AI";
      url = "https://crawl4ai.cnoe.localtest.me:8443";
      domain = "crawl4ai.cnoe.localtest.me";
      icon = iconPath "crawl4ai.svg";
      description = "Crawl4AI - Open-source LLM-friendly web crawler";
      categories = "Development;Network;";
      keywords = "crawl4ai;crawler;scraper;llm;ai;web;kubernetes;";
      scope = "https://crawl4ai.cnoe.localtest.me:8443/";
      ulid = "61ZKKF8QQHC7XYGFCWGMWY85CV";  # Generated 2026-01-12
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 102;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "crawl4ai.cnoe.localtest.me" ];
    }

    # AI Chatbot (Vercel AI SDK template - CNOE local)
    {
      name = "AI Chatbot";
      url = "https://ai-chatbot.cnoe.localtest.me:8443";
      domain = "ai-chatbot.cnoe.localtest.me";
      icon = iconPath "nextjs.svg";
      description = "Vercel AI SDK Chatbot - Next.js AI chat template";
      categories = "Development;Network;";
      keywords = "ai;chatbot;vercel;nextjs;llm;chat;kubernetes;";
      scope = "https://ai-chatbot.cnoe.localtest.me:8443/";
      ulid = "6EBKR8NA2A8TMS02SJ7NSR77RG";  # Generated 2026-01-12
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 103;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "ai-chatbot.cnoe.localtest.me" ];
    }

    # Open SWE (LangChain-based agent UI - CNOE local)
    {
      name = "Open SWE";
      url = "https://open-swe-ui.cnoe.localtest.me:8443";
      domain = "open-swe-ui.cnoe.localtest.me";
      icon = iconPath "open-swe.png";
      description = "Open SWE - LangChain-based asynchronous coding agent";
      categories = "Development;Network;";
      keywords = "open-swe;langchain;langgraph;agent;ai;coding;kubernetes;";
      scope = "https://open-swe-ui.cnoe.localtest.me:8443/";
      ulid = "5PCVTAVZTD0F050E23VXNXP7TK";  # Generated 2026-01-13
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 104;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "open-swe-ui.cnoe.localtest.me" ];
    }

    # Open WebUI (LLM interface - CNOE local)
    {
      name = "Open WebUI";
      url = "https://openwebui.cnoe.localtest.me:8443";
      domain = "openwebui.cnoe.localtest.me";
      icon = iconPath "openwebui.svg";
      description = "Open WebUI - Open source LLM user interface";
      categories = "Development;Network;";
      keywords = "openwebui;llm;ollama;chat;ai;interface;kubernetes;";
      scope = "https://openwebui.cnoe.localtest.me:8443/";
      ulid = "6M403VYCD36S0E6R0PTD2ZYA5M";  # Generated 2026-01-13
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 105;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "openwebui.cnoe.localtest.me" ];
    }

    # Phoenix Azire (CNOE local)
    {
      name = "Phoenix Azire";
      url = "https://phoenix.cnoe.localtest.me:8443";
      domain = "phoenix.cnoe.localtest.me";
      icon = iconPath "phoenix-azire.svg";
      description = "Phoenix Azire - AI observability and LLM tracing platform";
      categories = "Development;Network;";
      keywords = "phoenix;azire;ai;observability;tracing;llm;kubernetes;";
      scope = "https://phoenix.cnoe.localtest.me:8443/";
      ulid = "5A70F22AX1NP456PSAFESPEZ5E";  # Generated 2026-01-26
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 106;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "phoenix.cnoe.localtest.me" ];
    }

    # AI Workflow Builder (CNOE local)
    {
      name = "AI Workflow Builder";
      url = "https://workflow-builder.cnoe.localtest.me:8443";
      domain = "workflow-builder.cnoe.localtest.me";
      icon = iconPath "ai-workflow-builder.svg";
      description = "AI Workflow Builder - Visual node-based workflow automation editor";
      categories = "Development;Network;";
      keywords = "workflow;builder;visual;editor;automation;ai;nodes;react-flow;nextjs;";
      scope = "https://workflow-builder.cnoe.localtest.me:8443/";
      ulid = "31EYAA8SZG1WY6TCVYB2PJDNBM";  # Generated 2026-01-29
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 108;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "workflow-builder.cnoe.localtest.me" ];
    }

    # Redis Insights (CNOE local)
    {
      name = "Redis Insights";
      url = "https://redisinsight.cnoe.localtest.me:8443";
      domain = "redisinsight.cnoe.localtest.me";
      icon = iconPath "redis-insights.svg";
      description = "Redis Insights - Redis database management and visualization tool";
      categories = "Development;Network;";
      keywords = "redis;insights;database;cache;visualization;kubernetes;cnoe;";
      scope = "https://redisinsight.cnoe.localtest.me:8443/";
      ulid = "348E7WKJSMP0YRHTHEY3ETR5J6";  # Generated 2026-02-02
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 109;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "redisinsight.cnoe.localtest.me" ];
    }

    # Dify (CNOE local)
    {
      name = "Dify";
      url = "https://dify.cnoe.localtest.me:8443";
      domain = "dify.cnoe.localtest.me";
      icon = iconPath "dify.svg";
      description = "Dify - Open-source LLM app development platform and AI workflow builder";
      categories = "Development;Network;";
      keywords = "dify;ai;llm;workflow;builder;chatbot;agent;kubernetes;cnoe;";
      scope = "https://dify.cnoe.localtest.me:8443/";
      ulid = "53SPYVASDFAZCB0X58DZZS29Y4";  # Generated 2026-02-03
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 110;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "dify.cnoe.localtest.me" ];
    }

    # JupyterHub (CNOE local)
    {
      name = "JupyterHub";
      url = "https://jupyterhub.cnoe.localtest.me:8443";
      domain = "jupyterhub.cnoe.localtest.me";
      icon = iconPath "jupyterhub.svg";
      description = "JupyterHub - Multi-user Jupyter notebook server";
      categories = "Development;Network;Education;";
      keywords = "jupyter;jupyterhub;notebook;python;data-science;kubernetes;cnoe;";
      scope = "https://jupyterhub.cnoe.localtest.me:8443/";
      ulid = "1JJBSGAS1QBR1875WQ1NARB1YK";  # Generated 2026-02-03
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 111;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "jupyterhub.cnoe.localtest.me" ];
    }

    # KubeVela
    {
      name = "KubeVela";
      url = "https://velaux.cnoe.localtest.me:8443";
      domain = "velaux.cnoe.localtest.me";
      icon = iconPath "kubevela.svg";
      description = "KubeVela - Modern application delivery platform";
      categories = "Development;Network;Utility;";
      keywords = "kubevela;vela;velaux;kubernetes;k8s;deployment;oam;application;cnoe;";
      scope = "https://velaux.cnoe.localtest.me:8443/";
      ulid = "3037TSQ2W3RH3M7PRDBXFCT2K0";  # Generated 2026-02-04
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 112;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "velaux.cnoe.localtest.me" ];
    }

    # Activepieces (CNOE local)
    {
      name = "Activepieces";
      url = "https://activepieces.cnoe.localtest.me:8443";
      domain = "activepieces.cnoe.localtest.me";
      icon = iconPath "activepieces.svg";
      description = "Activepieces - Open source workflow automation platform";
      categories = "Development;Network;";
      keywords = "activepieces;automation;workflow;zapier;n8n;integrations;kubernetes;cnoe;";
      scope = "https://activepieces.cnoe.localtest.me:8443/";
      ulid = "7BW50E7SR9479J379C01JDP0Y6";  # Generated 2026-02-04
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 113;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "activepieces.cnoe.localtest.me" ];
    }

    # MCP Inspector (CNOE local)
    {
      name = "MCP Inspector";
      url = "https://mcp-inspector.cnoe.localtest.me:8443/?MCP_PROXY_PORT=8443";
      domain = "mcp-inspector.cnoe.localtest.me";
      icon = iconPath "mcp-inspector.svg";
      description = "MCP Inspector - Visual testing and debugging tool for MCP servers";
      categories = "Development;Network;";
      keywords = "mcp;inspector;model;context;protocol;debug;test;server;ai;";
      scope = "https://mcp-inspector.cnoe.localtest.me:8443/";
      ulid = "39ADZC4WY3Y4AKR1YVSZDR1NKQ";  # Generated 2026-02-11
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 114;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "mcp-inspector.cnoe.localtest.me" ];
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

    # Flowise
    {
      name = "Flowise";
      url = "https://flowise.cnoe.localtest.me:8443";
      domain = "flowise.cnoe.localtest.me";
      icon = "/etc/nixos/assets/icons/flowise.svg";
      description = "Flowise - Build AI Agents, Visually";
      categories = "Development;Network;";
      keywords = "flowise;ai;agent;flow;langchain;llm;chatbot;workflow;";
      scope = "https://flowise.cnoe.localtest.me:8443/";
      ulid = "36G226WSWG11H0T2ACVZ6FZXCN";  # Generated 2026-02-12
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 115;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "flowise.cnoe.localtest.me" ];
    }

    # Mastra Playground
    {
      name = "Mastra Playground";
      url = "https://mastra-playground.cnoe.localtest.me/";
      domain = "mastra-playground.cnoe.localtest.me";
      icon = "/etc/nixos/assets/icons/mastra-playground.svg";
      description = "Mastra Playground - AI agent framework testing environment";
      categories = "Development;Network;";
      keywords = "mastra;ai;agent;playground;typescript;framework;llm;";
      scope = "https://mastra-playground.cnoe.localtest.me/";
      ulid = "34C8ASD2334ZVN4KP7JX1TJHPH";  # Generated 2026-02-14
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 78;
      preferred_monitor_role = "secondary";
      # Feature 113: URL routing domains
      routing_domains = [ "mastra-playground.cnoe.localtest.me" ];
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
