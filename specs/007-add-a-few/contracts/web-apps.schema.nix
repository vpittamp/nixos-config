# Contract Schema: Web Applications Declarative Configuration
# Module: home-modules/tools/web-apps-declarative.nix
# Purpose: Define the configuration contract for declarative web application launcher

{ lib, ... }:

{
  # Web applications declarative configuration
  programs.webApps = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable declarative web application launcher system";
    };

    browser = lib.mkOption {
      type = lib.types.enum [ "ungoogled-chromium" "chromium" "google-chrome" ];
      default = "ungoogled-chromium";
      description = "Browser to use for web applications";
    };

    baseProfileDir = lib.mkOption {
      type = lib.types.str;
      default = "$HOME/.local/share/webapps";
      description = "Base directory for web application browser profiles";
    };

    applications = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Display name for the web application";
            example = "Gmail";
          };

          url = lib.mkOption {
            type = lib.types.strMatching "^https?://.*";
            description = "URL of the web application";
            example = "https://mail.google.com";
          };

          wmClass = lib.mkOption {
            type = lib.types.strMatching "^webapp-[a-z0-9-]+$";
            description = ''
              Window manager class for targeting in i3wm.
              Must start with 'webapp-' and contain only lowercase letters, numbers, and hyphens.
            '';
            example = "webapp-gmail";
          };

          icon = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "Path to custom icon file (PNG, SVG)";
            example = ./assets/webapp-icons/gmail.png;
          };

          workspace = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Preferred i3wm workspace for this application";
            example = "2";
          };

          lifecycle = lib.mkOption {
            type = lib.types.enum [ "persistent" "fresh" ];
            default = "persistent";
            description = ''
              Lifecycle management:
              - persistent: Keep running, reconnect to existing window
              - fresh: Launch new instance each time
            '';
          };

          keywords = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Additional search keywords for rofi launcher";
            example = [ "email" "mail" "google" ];
          };

          enabled = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether this web application is enabled";
          };

          extraBrowserArgs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Additional command-line arguments for the browser";
            example = [ "--disable-notifications" "--force-dark-mode" ];
          };
        };
      });
      default = {};
      description = ''
        Declarative web application definitions.
        Each attribute name becomes the application ID.
      '';
      example = lib.literalExpression ''
        {
          gmail = {
            name = "Gmail";
            url = "https://mail.google.com";
            wmClass = "webapp-gmail";
            icon = ./assets/webapp-icons/gmail.png;
            workspace = "2";
            keywords = [ "email" "mail" "google" ];
          };
          notion = {
            name = "Notion";
            url = "https://www.notion.so";
            wmClass = "webapp-notion";
            workspace = "3";
          };
        }
      '';
    };

    rofi = {
      showIcons = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Show icons in rofi launcher";
      };
    };

    i3Integration = {
      autoAssignWorkspace = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Automatically assign web applications to their preferred workspaces.
          Generates i3wm 'assign' directives.
        '';
      };

      floatingMode = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Launch web applications in floating mode by default";
      };
    };
  };

  # Validation assertions
  config = lib.mkIf config.programs.webApps.enable {
    assertions = [
      {
        assertion = builtins.all
          (app: app.wmClass != null && lib.hasPrefix "webapp-" app.wmClass)
          (lib.attrValues config.programs.webApps.applications);
        message = "All web applications must have wmClass starting with 'webapp-'";
      }
      {
        assertion =
          let
            wmClasses = lib.mapAttrsToList (id: app: app.wmClass)
              (lib.filterAttrs (id: app: app.enabled) config.programs.webApps.applications);
          in
          (lib.length wmClasses) == (lib.length (lib.unique wmClasses));
        message = "Web application wmClass values must be unique across all enabled applications";
      }
      {
        assertion = builtins.all
          (app: app.icon == null || builtins.pathExists app.icon)
          (lib.attrValues config.programs.webApps.applications);
        message = "Web application icon paths must exist if specified";
      }
    ];
  };
}
