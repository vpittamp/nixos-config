# PWA Definitions Module
# Centralized configuration for Firefox PWA applications
{ config, lib, pkgs, ... }:

with lib;

{
  options.services.pwaDefinitions = {
    enable = mkEnableOption "PWA definitions for firefoxpwa";
    
    pwas = mkOption {
      type = types.attrs;
      default = {};
      description = "PWA definitions to be used by firefoxpwa-declarative module";
    };
  };

  config = mkIf config.services.pwaDefinitions.enable {
    services.pwaDefinitions.pwas = {
      # PWAs with valid manifests
      github = {
        name = "GitHub";
        url = "https://github.com";
        manifest = "https://github.com/manifest.json";
        icon = "/etc/nixos/assets/icons/pwas/github.png";
        iconUrl = "https://github.githubassets.com/favicons/favicon-dark.svg";
        categories = "Development";
        keywords = "git,code,repository,version control";
        description = "Code hosting and collaboration platform";
      };

      claude = {
        name = "Claude";
        url = "https://claude.ai";
        manifest = "https://claude.ai/manifest.json";
        iconUrl = "https://claude.ai/favicon.ico";
        categories = "Utility;Science";
        keywords = "ai,assistant,anthropic";
        description = "Claude AI Assistant by Anthropic";
      };

      youtube = {
        name = "YouTube";
        url = "https://www.youtube.com";
        manifest = "https://www.youtube.com/manifest.json";
        icon = "/etc/nixos/assets/icons/pwas/youtube.png";
        iconUrl = "https://www.youtube.com/s/desktop/4965577f/img/favicon_144x144.png";
        categories = "AudioVideo;Video";
        keywords = "video,streaming,media,entertainment";
        description = "Video sharing and streaming platform";
      };

      # PWAs that may need fallback
      chatgpt = {
        name = "ChatGPT";
        url = "https://chatgpt.com";
        manifest = "https://chatgpt.com/manifest.json";  # May not exist
        icon = "/etc/nixos/assets/icons/pwas/chatgpt.png";
        iconUrl = "https://cdn.oaistatic.com/_next/static/media/apple-touch-icon.82af6fe1.png";
        categories = "Utility;Science";
        keywords = "ai,chat,openai,gpt";
        description = "OpenAI ChatGPT Assistant";
      };

      google = {
        name = "Google";
        url = "https://www.google.com";
        manifest = "https://www.google.com/manifest.json";
        icon = "/etc/nixos/assets/icons/pwas/google-ai.png";
        categories = "Network;WebBrowser";
        keywords = "search,google";
        description = "Google Search";
      };

      # Development tools PWAs (with existing IDs if already installed)
      argocd = {
        name = "ArgoCD";
        url = "https://argocd.cnoe.localtest.me:8443";
        manifest = "https://argocd.cnoe.localtest.me:8443/manifest.json";
        id = "01CBD2EC47D2F8D8CF86034280";  # Existing ID
        categories = "Development;Utility";
        keywords = "kubernetes,gitops,deployment";
        description = "GitOps continuous delivery for Kubernetes";
      };

      backstage = {
        name = "Backstage";
        url = "https://backstage.cnoe.localtest.me:8443";
        manifest = "https://backstage.cnoe.localtest.me:8443/manifest.json";
        id = "0199D501A20B94AE3BB038B6BC";  # Existing ID
        categories = "Development";
        keywords = "platform,developer,portal";
        description = "Open platform for building developer portals";
      };

      # Social media PWAs
      twitter = {
        name = "X (Twitter)";
        url = "https://x.com";
        manifest = "https://x.com/manifest.json";
        iconUrl = "https://abs.twimg.com/responsive-web/client-web/icon-ios.77d25eba.png";
        categories = "Network;InstantMessaging";
        keywords = "social,twitter,x,microblogging";
        description = "Social media and microblogging platform";
      };

      linkedin = {
        name = "LinkedIn";
        url = "https://www.linkedin.com";
        manifest = "https://www.linkedin.com/manifest.json";
        iconUrl = "https://static.licdn.com/aero-v1/sc/h/al2o9zrvru7aqj8e1x2rzsrca";
        categories = "Network;Office";
        keywords = "professional,networking,jobs,career";
        description = "Professional networking platform";
      };

      # Communication PWAs  
      slack = {
        name = "Slack";
        url = "https://app.slack.com";
        manifest = "https://app.slack.com/manifest.json";
        iconUrl = "https://a.slack-edge.com/80588/marketing/img/icons/icon_slack.png";
        categories = "Network;InstantMessaging";
        keywords = "chat,team,collaboration,messaging";
        description = "Team collaboration and messaging";
      };

      discord = {
        name = "Discord";
        url = "https://discord.com/app";
        manifest = "https://discord.com/manifest.json";
        iconUrl = "https://discord.com/assets/847541504914fd33810e70a0ea73177e.ico";
        categories = "Network;InstantMessaging;AudioVideo";
        keywords = "chat,voice,gaming,community";
        description = "Voice, video and text communication";
      };

      # Productivity PWAs
      notion = {
        name = "Notion";
        url = "https://www.notion.so";
        manifest = "https://www.notion.so/manifest.json";
        iconUrl = "https://www.notion.so/images/favicon.ico";
        categories = "Office;Utility";
        keywords = "notes,wiki,database,productivity";
        description = "All-in-one workspace for notes and collaboration";
      };

      gmail = {
        name = "Gmail";
        url = "https://mail.google.com";
        manifest = "https://mail.google.com/mail/manifest.json";
        iconUrl = "https://ssl.gstatic.com/ui/v1/icons/mail/rfr/gmail.ico";
        categories = "Network;Email";
        keywords = "email,mail,google";
        description = "Google email service";
      };

      # Development PWAs
      gitlab = {
        name = "GitLab";
        url = "https://gitlab.com";
        manifest = "https://gitlab.com/manifest.json";
        iconUrl = "https://gitlab.com/assets/favicon-7901bd695fb93edb07975966062049829afb56cf11511236e61bcf425070e36e.png";
        categories = "Development";
        keywords = "git,code,repository,ci,cd";
        description = "DevOps platform for git repositories";
      };

      vscode = {
        name = "VS Code Web";
        url = "https://vscode.dev";
        manifest = "https://vscode.dev/manifest.json";
        iconUrl = "https://vscode.dev/static/stable/favicon.ico";
        categories = "Development;TextEditor";
        keywords = "code,editor,ide,development";
        description = "Visual Studio Code in the browser";
      };
    };
  };
}
