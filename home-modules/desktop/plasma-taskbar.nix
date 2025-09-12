
{ config, lib, pkgs, ... }:

let
  hasGui = config.services.xserver.enable or false;
  ensureBin = pkgs.writeShellScriptBin "ensure-plasma-panels" ''
    set -euo pipefail
    QDBUS=${pkgs.qt6.qttools}/bin/qdbus
    for i in $(seq 1 30); do
      if "$QDBUS" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '""' >/dev/null 2>&1; then
        break
      fi
      sleep 1
    done
    "$QDBUS" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript < "${config.home.homeDirectory}/.config/plasma-panels/ensure-panels.js"
  '';
in
{
  config = lib.mkIf hasGui {
    home.packages = [ pkgs.qt6.qttools ];

    home.file.".config/plasma-panels/ensure-panels.js".text = ''
      function panelsList() {
        try { return panels(); } catch (e) {}
        try {
          var list = [];
          var ids = panelIds;
          for (var i = 0; i < ids.length; ++i) {
            list.push(panelById(ids[i]));
          }
          return list;
        } catch (e2) {}
        return [];
      }

      function widgetIdsOf(panel) {
        try { return panel.widgetIds; } catch (e) {}
        try { return panel.widgets(); } catch (e2) {}
        return [];
      }

      function widgetBy(panel, id) {
        try { return panel.widgetById(id); } catch (e) {}
        return id;
      }

      function ensureTaskManager(panel) {
        var ids = widgetIdsOf(panel);
        var tm = null;
        for (var i = 0; i < ids.length; ++i) {
          var w = widgetBy(panel, ids[i]);
          if (w && w.type && (w.type.indexOf("org.kde.plasma.taskmanager") >= 0)) {
            tm = w; break;
          }
        }
        if (!tm) {
          tm = panel.addWidget("org.kde.plasma.taskmanager");
        }
        if (tm) {
          tm.currentConfigGroup = ["General"];
          tm.writeConfig("showOnlyCurrentScreen", "true");
        }
      }

      var currentPanels = panelsList();
      for (var s = 0; s < screenCount; ++s) {
        var pForScreen = null;
        for (var i = 0; i < currentPanels.length; ++i) {
          var p = currentPanels[i];
          if (p && p.screen === s) { pForScreen = p; break; }
        }
        if (!pForScreen) {
          pForScreen = new Panel;
          pForScreen.location = "bottom";
          pForScreen.screen = s;
        }
        ensureTaskManager(pForScreen);
        if (pForScreen.reloadConfig) { pForScreen.reloadConfig(); }
      }
    '';

    systemd.user.services."plasma-ensure-panels" = {
      Unit = {
        Description = "Ensure Plasma taskbar per monitor and current-screen tasks";
        After = [ "graphical-session.target" "plasma-plasmashell.service" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        Environment = [ "XDG_RUNTIME_DIR=%t" ];
        ExecStart = "${ensureBin}/bin/ensure-plasma-panels";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
