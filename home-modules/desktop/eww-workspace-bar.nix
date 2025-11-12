{ config, lib, pkgs, osConfig ? null, ... }:

let
  cfg = config.programs.eww-workspace-bar;
  isHeadless = osConfig != null && (osConfig.networking.hostName or "") == "nixos-hetzner-sway";

  # Feature 057: Import unified theme colors (Catppuccin Mocha)
  # Use the same color palette as unified-bar-theme.nix
  mocha = {
    base = "#1e1e2e";
    mantle = "#181825";
    surface0 = "#313244";
    surface1 = "#45475a";
    overlay0 = "#6c7086";
    text = "#cdd6f4";
    subtext0 = "#a6adc8";
    blue = "#89b4fa";
    mauve = "#cba6f7";
    yellow = "#f9e2af";
    red = "#f38ba8";
    green = "#a6e3a1";
    teal = "#94e2d5";
  };

  workspaceOutputs =
    if isHeadless then [
      { name = "HEADLESS-1"; label = "Headless 1"; }
      { name = "HEADLESS-2"; label = "Headless 2"; }
      { name = "HEADLESS-3"; label = "Headless 3"; }
    ] else [
      { name = "eDP-1"; label = "Built-in"; }
    ];

  sanitize = name:
    lib.toLower (
      lib.replaceStrings [" " ":" "/" "_" "-"] ["-" "-" "-" "-" "-"] name
    );

  sanitizeVar = name:
    lib.toLower (
      lib.replaceStrings [" " ":" "/" "-" "."] ["_" "_" "_" "_" "_"] name
    );

  pythonEnv = pkgs.python311.withPackages (ps: with ps; [ i3ipc pyxdg pydantic ]);

  # Feature 057: Shared module directory for icon_resolver.py, models.py
  # Copy all Python modules from source directory
  workspacePanelDir = pkgs.stdenv.mkDerivation {
    name = "sway-workspace-panel-v2";  # Changed name to force rebuild after adding window_id
    # Feature 059: Fixed import path + added window_id field (v4 - force rebuild with window_id)
    src = ../tools/sway-workspace-panel;
    installPhase = ''
      mkdir -p $out
      echo "DEBUG: Contents of source directory:" >&2
      ls -laR . >&2
      cp *.py $out/
      cp workspace-preview-daemon $out/
      # Feature 059: Copy selection_models directory for Pydantic models (includes __init__.py and selection_state.py)
      if [ -d selection_models ]; then
        echo "DEBUG: Found selection_models directory, copying..." >&2
        cp -r selection_models $out/
      else
        echo "ERROR: selection_models directory not found!" >&2
        exit 1
      fi
      chmod +x $out/workspace_panel.py
      chmod +x $out/workspace-preview-daemon
    '';
  };

  workspacePanelScript = "${workspacePanelDir}/workspace_panel.py";

  workspacePanelBin = pkgs.writeShellScriptBin "sway-workspace-panel" ''
    export PYTHONPATH="${workspacePanelDir}:$PYTHONPATH"
    exec ${pythonEnv}/bin/python -u ${workspacePanelScript} "$@"
  '';

  # Use PATH instead of hardcoded Nix store path to avoid stale config after rebuilds
  workspacePanelCommand = "sway-workspace-panel";

  # Feature 057: User Story 2 - Workspace Preview Daemon
  workspacePreviewDaemonScript = "${workspacePanelDir}/workspace-preview-daemon";

  workspacePreviewDaemonBin = pkgs.writeShellScriptBin "workspace-preview-daemon" ''
    export PYTHONPATH="${workspacePanelDir}:$PYTHONPATH"
    exec ${pythonEnv}/bin/python -u ${workspacePreviewDaemonScript} "$@"
  '';

  workspacePreviewCommand = "workspace-preview-daemon";

  ewwConfigDir = "eww-workspace-bar";
  ewwConfigPath = "%h/.config/${ewwConfigDir}";

  markupVar = output: "workspace_rows_" + sanitizeVar output.name;

  workspaceMarkupDefs = lib.concatStringsSep "\n\n" (map (output:
    let
      varName = markupVar output;
    in
      ''
(deflisten ${varName} :initial "" "${workspacePanelCommand} --format yuck --output ${output.name}")
      ''
  ) workspaceOutputs);

  # Feature 057: User Story 2 - Workspace Preview (T038)
  workspacePreviewDefs = ''
;; Feature 057: User Story 2 - Workspace Preview Card
;; Subscribes to workspace_mode events from i3pm daemon
;; Outputs line-delimited JSON with workspace contents
(deflisten workspace_preview_data
  :initial "{\"visible\": false}"
  "${workspacePreviewCommand}")
  '';

  windowBlocks = lib.concatStringsSep "\n\n" (map (output:
    let
      windowId = "workspace-bar-" + sanitize output.name;
      varName = markupVar output;
    in
      ''
(defwindow ${windowId}
  :monitor "${output.name}"
  :windowtype "dock"
  :exclusive true
  :focusable false
  :geometry (geometry :anchor "bottom center"
                        :x "0px"
                        :y "0px"
                        :width "100%"
                        :height "32px")
  :reserve (struts :side "bottom" :distance "36px")
  (workspace-strip :output_label "${output.label}" :markup_var ${varName})
)
      ''
  ) workspaceOutputs);

  ewwYuck = ''
${workspaceMarkupDefs}

${workspacePreviewDefs}

;; Feature 057: User Story 2 - Workspace Preview Card Widget (T041)
;; Enhanced with prominent mode + digits display (Option 1 UX)
(defwidget workspace-preview-card []
  (box :class "preview-card"
       :orientation "v"
       :space-evenly false
       :visible {workspace_preview_data.visible == true}

    ;; Option A: Unified Smart Detection - Project Mode Preview
    (box :class "project-preview"
         :orientation "v"
         :space-evenly false
         :visible {workspace_preview_data.type == "project"}
      ;; Project search header with icon
      (box :class "preview-header"
           :orientation "v"
           :halign "center"
        (label :class "preview-mode-digits"
               :text {"🔍 " + workspace_preview_data.accumulated_chars})
        ;; Project match with icon
        (box :class "project-match-box"
             :orientation "h"
             :space-evenly false
             :spacing 8
             :halign "center"
             :visible {workspace_preview_data.matched_project != ""}
          (label :class "project-icon"
                 :text {workspace_preview_data.project_icon ?: "📁"})
          (label :class "preview-subtitle"
                 :text {"Project: " + workspace_preview_data.matched_project}))
        ;; No match / searching text
        (label :class "preview-subtitle"
               :visible {workspace_preview_data.matched_project == ""}
               :text {workspace_preview_data.no_match == true
                      ? "No project found"
                      : "Type project name..."}))
      ;; Match indicator
      (box :class "preview-body"
           :orientation "v"
           :halign "center"
        (label :class {workspace_preview_data.matched_project != "" ? "preview-match" : "preview-no-match"}
               :text {workspace_preview_data.matched_project != ""
                      ? "✓ Match found - Press Enter"
                      : (workspace_preview_data.no_match == true
                         ? "No matches - Try different letters"
                         : "")})))

    ;; Feature 072: T020-T024 - All Windows Preview (User Story 1)
    (box :class "all-windows-preview"
         :orientation "v"
         :space-evenly false
         :visible {workspace_preview_data.type == "all_windows"}
      ;; Header with counts
      (box :class "preview-header"
           :orientation "v"
           :halign "center"
        (label :class "preview-mode-digits"
               :text "🪟 All Windows")
        (label :class "preview-subtitle"
               :text {workspace_preview_data.total_window_count + " window" +
                      (workspace_preview_data.total_window_count != 1 ? "s" : "") +
                      " across " + workspace_preview_data.total_workspace_count +
                      " workspace" + (workspace_preview_data.total_workspace_count != 1 ? "s" : "")}))

      ;; Instructional state (when no digits typed yet)
      (box :class "preview-body"
           :orientation "v"
           :halign "center"
           :visible {workspace_preview_data.instructional == true}
        (label :class "preview-subtitle"
               :text "Type workspace number to filter, or :project for project mode"))

      ;; Empty state (no windows open anywhere)
      (box :class "preview-body"
           :orientation "v"
           :halign "center"
           :visible {workspace_preview_data.empty == true && workspace_preview_data.instructional != true}
        (label :class "preview-empty"
               :text "No windows open"))

      ;; Scrollable workspace groups list (Feature 072: T021)
      (scroll :class "workspace-groups-scroll"
              :vscroll true
              :hscroll false
              :height 600
              :visible {workspace_preview_data.empty == false && workspace_preview_data.instructional != true}
        (box :class "workspace-groups"
             :orientation "v"
             :space-evenly false
             :spacing 12
          (for group in {workspace_preview_data.workspace_groups ?: []}
            (box :class "workspace-group"
                 :orientation "v"
                 :space-evenly false
                 :spacing 4
              ;; Workspace header (workspace number + window count + monitor)
              ;; Feature 059: Add selection highlight for workspace headings
              ;; Feature 059: T025 - Add move-mode variant for peach accent
              (box :class {"workspace-group-header" +
                           ((workspace_preview_data.selection_state?.item_type == "workspace_heading" &&
                             workspace_preview_data.selection_state?.workspace_num == group.workspace_num)
                            ? (workspace_preview_data.selection_state?.move_mode ? " selected-move-mode" : " selected")
                            : "")}
                   :orientation "h"
                   :space-evenly false
                   :spacing 8
                (label :class "workspace-group-number"
                       :text {"Workspace " + group.workspace_num + ((group.workspace_name ?: "") != "" ? " (" + group.workspace_name + ")" : "")})
                (label :class "workspace-group-count"
                       :text {group.window_count + " window" + (group.window_count != 1 ? "s" : "")})
                (label :class "workspace-group-monitor"
                       :text {group.monitor_output}))

              ;; Window entries for this workspace
              (box :class "workspace-group-windows"
                   :orientation "v"
                   :space-evenly false
                   :spacing 4
                (for window in {group.windows ?: []}
                  ;; Feature 059: Add selection highlight for windows
                  ;; Feature 059: T025 - Add move-mode variant for peach accent
                  (box :class {"preview-app" +
                               (window.focused ? " focused" : "") +
                               ((workspace_preview_data.selection_state?.item_type == "window" &&
                                 workspace_preview_data.selection_state?.window_id == window.window_id)
                                ? (workspace_preview_data.selection_state?.move_mode ? " selected-move-mode" : " selected")
                                : "")}
                       :orientation "h"
                       :space-evenly false
                       :spacing 8
                    (image :class "preview-app-icon"
                           :path {window.icon_path != "" ? window.icon_path : ""}
                           :image-width 24
                           :image-height 24)
                    (label :class "preview-app-name"
                           :text {window.name}
                           :limit-width 30
                           :truncate true))))))))

      ;; Footer: Truncation indicator if more than 20 workspaces
      (box :class "preview-footer"
           :visible {(workspace_preview_data.total_workspace_count ?: 0) > 20}
        (label :class "preview-count"
               :text {"... and " + ((workspace_preview_data.total_workspace_count ?: 0) - 20) + " more workspaces (type digits to filter)"})))

    ;; Workspace Mode Preview (existing functionality)
    (box :class "workspace-preview"
         :orientation "v"
         :space-evenly false
         :visible {workspace_preview_data.type != "project" && workspace_preview_data.type != "all_windows"}
      ;; Enhanced Header: Prominent mode + digits, then descriptive subtitle
      (box :class "preview-header"
           :orientation "v"
           :space-evenly false
           :halign "center"
        ;; Primary: Large mode symbol + accumulated digits (or placeholder if instructional)
        (label :class "preview-mode-digits"
               :halign "center"
               :text {workspace_preview_data.instructional == true
                      ? (workspace_preview_data.mode == "move" ? "⇒ __" : "→ __")
                      : (workspace_preview_data.mode == "move" ? "⇒ " : "→ ") +
                        (workspace_preview_data.accumulated_digits ?: workspace_preview_data.workspace_num)})
        ;; Secondary: Descriptive subtitle (or instructional text)
        (label :class "preview-subtitle"
               :halign "center"
               :text {workspace_preview_data.instructional == true
                      ? (workspace_preview_data.mode == "move"
                         ? "Type workspace + monitor (e.g., 231 = WS 23 → Monitor 1)"
                         : "Type workspace number...")
                      : (workspace_preview_data.mode == "move"
                         ? (workspace_preview_data.target_monitor != ""
                            ? "Move WS " + workspace_preview_data.workspace_num + " → " + workspace_preview_data.target_monitor
                            : "Move workspace (type monitor: 1-3)")
                         : "Navigate to Workspace " + workspace_preview_data.workspace_num)}))

      ;; Empty workspace indicator (hidden in instructional mode)
      (box :class "preview-body"
           :orientation "v"
           :visible {workspace_preview_data.empty == true && workspace_preview_data.instructional != true}
        (label :class "preview-empty"
               :text "Empty workspace"))

      ;; App list (when not empty, hidden in instructional mode)
      (box :class "preview-apps"
           :orientation "v"
           :space-evenly false
           :spacing 4
           :visible {workspace_preview_data.empty == false && workspace_preview_data.instructional != true}
        (for app in {workspace_preview_data.apps ?: []}
          (box :class {"preview-app" + (app.focused ? " focused" : "")}
               :orientation "h"
               :space-evenly false
               :spacing 8
            (image :class "preview-app-icon"
                   :path {app.icon_path != "" ? app.icon_path : ""}
                   :image-width 24
                   :image-height 24)
            (label :class "preview-app-name"
                   :text {app.name}
                   :limit-width 30
                   :truncate true))))

      ;; Footer: Window count (hidden in instructional mode)
      (box :class "preview-footer"
           :visible {workspace_preview_data.empty == false && workspace_preview_data.instructional != true}
        (label :class "preview-count"
               :text {workspace_preview_data.window_count + " window" + (workspace_preview_data.window_count != 1 ? "s" : "")})))))

;; Feature 057: User Story 2 - Preview Overlay Window (T038, T040)
;; Multi-monitor support: :monitor property dynamically set from workspace_preview_data
;; Window visibility controlled by eww open/close commands (not :visible property)
;; This ensures GTK creates window surface that Sway can see in its tree
(defwindow workspace-preview
  :monitor "${if isHeadless then "HEADLESS-1" else "eDP-1"}"
  :windowtype "normal"
  :stacking "overlay"
  :focusable false
  :exclusive false
  :geometry (geometry :anchor "center"
                      :x "0px"
                      :y "0px"
                      :width "600px"
                      :height "800px")
  (workspace-preview-card))

(defwidget workspace-button [number_label workspace_name app_name icon_path icon_fallback workspace_id focused visible urgent pending empty]
  (button
    :class {
      "workspace-button "
      + (pending ? "pending " : "")
      + (focused ? "focused " : "")
      + ((visible && !focused) ? "visible " : "")
      + (urgent ? "urgent " : "")
      + ((icon_path != "") ? "has-icon " : "no-icon ")
      + (empty ? "empty" : "populated")
    }
    :tooltip { app_name != "" ? (number_label + " · " + app_name) : workspace_name }
    :onclick {
      "swaymsg workspace \""
      + replace(workspace_name, "\"", "\\\"")
      + "\""
    }
    (box :class "workspace-pill" :orientation "h" :space-evenly false :spacing 3
      (image :class "workspace-icon-image"
             :path icon_path
             :image-width 16
             :image-height 16)
      (label :class "workspace-number" :text number_label)))
)

(defwidget workspace-strip [output_label markup_var]
  (box :class "workspace-bar"
    (label :class "workspace-output" :text output_label)
    (box :class "workspace-strip"
         :orientation "h"
         :halign "center"
          :spacing 3
      (literal :content markup_var))))

${windowBlocks}
'';

  ewwScss = ''
/* Feature 057: Unified theme colors from unified-bar-theme.nix */
/* Catppuccin Mocha color palette */
$base: ${mocha.base};
$mantle: ${mocha.mantle};
$surface0: ${mocha.surface0};
$surface1: ${mocha.surface1};
$overlay0: ${mocha.overlay0};
$text: ${mocha.text};
$subtext0: ${mocha.subtext0};
$mauve: ${mocha.mauve};
$blue: ${mocha.blue};
$teal: ${mocha.teal};
$red: ${mocha.red};
$yellow: ${mocha.yellow};
$green: ${mocha.green};

* {
  font-family: sans-serif;
  font-size: 11pt;
  color: $text;
  background-color: transparent;
}

window {
  background-color: transparent;
}

.workspace-bar {
  background: rgba(30, 30, 46, 0.85);
  padding: 4px 8px;
  margin: 6px;
  border-radius: 6px;
  border: 1px solid rgba(203, 166, 247, 0.25);
  box-shadow: 0 2px 10px rgba(0, 0, 0, 0.4);
}

.workspace-output {
  font-size: 8pt;
  color: $subtext0;
  margin-right: 8px;
  opacity: 0.5;
}

.workspace-strip {
  margin-left: 0px;
}

/* Flat buttons with subtle borders */
.workspace-button {
  background: rgba(30, 30, 46, 0.3);
  padding: 3px 6px;
  border-radius: 4px;
  border: 1px solid rgba(108, 112, 134, 0.3);
  box-shadow: none;
  min-width: 0;
  transition: all 0.2s;
}

button {
  box-shadow: none;
  background-image: none;
  outline: none;
}

.workspace-button:hover {
  background: rgba(137, 180, 250, 0.15);
  border: 1px solid rgba(137, 180, 250, 0.4);
}

/* Focused: Flat blue accent */
.workspace-button.focused {
  background: rgba(137, 180, 250, 0.3);
  border: 1px solid rgba(137, 180, 250, 0.6);
}

/* Visible on other monitor */
.workspace-button.visible:not(.focused) {
  background: rgba(137, 180, 250, 0.12);
  border: 1px solid rgba(137, 180, 250, 0.35);
}

.workspace-button.urgent {
  background: rgba(243, 139, 168, 0.25);
  border: 1px solid rgba(243, 139, 168, 0.5);
}

.workspace-button.empty {
  opacity: 0.3;
}

.workspace-button.empty:hover {
  opacity: 0.6;
}

/* Feature 058: Pending workspace highlight (User Story 1) */
.workspace-button.pending {
  background: rgba(249, 226, 175, 0.25);  /* Catppuccin Mocha Yellow */
  border: 1px solid rgba(249, 226, 175, 0.7);
  transition: all 0.2s;  /* Smooth transitions (T018) */
}

.workspace-button.pending .workspace-icon-image {
  -gtk-icon-shadow: 0 0 8px rgba(249, 226, 175, 0.8);  /* Icon glow */
}

.workspace-button.pending .workspace-number {
  color: $yellow;
  font-weight: 600;
}

/* T019: Pending overrides focused (mutual exclusion) */
.workspace-button.pending.focused {
  background: rgba(249, 226, 175, 0.25);  /* Pending takes priority */
  border: 1px solid rgba(249, 226, 175, 0.7);
}

.workspace-button.pending.focused .workspace-icon-image {
  -gtk-icon-shadow: 0 0 8px rgba(249, 226, 175, 0.8);  /* Pending icon glow */
}

.workspace-button.pending.focused .workspace-number {
  color: $yellow;  /* Pending color overrides blue focused color */
  font-weight: 600;
}

.workspace-pill {
  margin: 0;
  padding: 0;
}

.workspace-icon-image {
  opacity: 1.0;
  min-width: 16px;
  min-height: 16px;
}

.workspace-button.focused .workspace-icon-image {
  -gtk-icon-shadow: 0 0 8px rgba(137, 180, 250, 0.8);
}

.workspace-button.urgent .workspace-icon-image {
  -gtk-icon-shadow: 0 0 6px rgba(243, 139, 168, 0.5);
}

/* Hide icon when no icon path */
.workspace-button.no-icon .workspace-icon-image {
  opacity: 0;
}

/* Workspace number always visible */
.workspace-number {
  font-size: 9pt;
  font-weight: 500;
  color: $subtext0;
  min-width: 12px;
}

.workspace-button.focused .workspace-number {
  color: $blue;
  font-weight: 600;
}

.workspace-button.urgent .workspace-number {
  color: $red;
  font-weight: 600;
}

.workspace-button.empty .workspace-number {
  color: $overlay0;
}

/* Feature 057: User Story 2 - Workspace Preview Card Styling (T039) */
/* Catppuccin Mocha theme with semi-transparent background */

/* Wrapper ensures window always has content for GTK */
.preview-wrapper {
  min-width: 600px;
  min-height: 800px;
}

.preview-card {
  background: rgba(30, 30, 46, 0.95);  /* $base with opacity */
  padding: 16px;
  border-radius: 8px;
  border: 2px solid rgba(203, 166, 247, 0.4);  /* $mauve */
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.6);
  min-width: 400px;
  min-height: 150px;
}

.preview-header {
  margin-bottom: 12px;
  padding-bottom: 12px;
  border-bottom: 1px solid rgba(108, 112, 134, 0.3);  /* $overlay0 */
}

/* Enhanced header: Prominent mode + digits display (Option 1 UX) */
.preview-mode-digits {
  font-size: 28pt;
  font-weight: 700;
  color: $yellow;  /* Catppuccin yellow for pending state */
  margin-bottom: 4px;
  letter-spacing: 0.5px;
  text-shadow: 0 0 12px rgba(249, 226, 175, 0.4);  /* Subtle glow */
}

.preview-subtitle {
  font-size: 10pt;
  font-weight: 400;
  color: $subtext0;
  opacity: 0.8;
}

.preview-body {
  padding: 20px 0;
}

.preview-empty {
  font-size: 10pt;
  color: $subtext0;
  font-style: italic;
}

.preview-apps {
  padding: 4px 0;
  min-height: 50px;
}

.preview-app {
  padding: 6px 8px;
  border-radius: 4px;
  background: rgba(49, 50, 68, 0.4);  /* $surface0 with opacity */
  transition: all 0.2s;
}

.preview-app:hover {
  background: rgba(49, 50, 68, 0.6);
}

.preview-app.focused {
  background: rgba(137, 180, 250, 0.25);  /* $blue with opacity */
  border: 1px solid rgba(137, 180, 250, 0.5);
}

/* Feature 059: Arrow key selection highlight */
.preview-app.selected {
  background: rgba(137, 180, 250, 0.2);  /* $blue at 20% opacity */
  border-left: 3px solid rgba(137, 180, 250, 0.8);
  transition: background 0.2s ease-in-out, border 0.2s ease-in-out;
}

.preview-workspace-heading.selected {
  background: rgba(137, 180, 250, 0.2);  /* $blue at 20% opacity */
  border-left: 3px solid rgba(137, 180, 250, 0.8);
  transition: background 0.2s ease-in-out, border 0.2s ease-in-out;
}

/* Feature 059: Move mode selection (peach accent) */
.preview-app.selected-move-mode {
  background: rgba(250, 179, 135, 0.2);  /* $peach at 20% opacity */
  border-left: 3px solid rgba(250, 179, 135, 0.8);
}

.preview-workspace-heading.selected-move-mode {
  background: rgba(250, 179, 135, 0.2);  /* $peach at 20% opacity */
  border-left: 3px solid rgba(250, 179, 135, 0.8);
}

/* Feature 059: Improve text readability on selected items */
.preview-app.selected .preview-app-name,
.preview-workspace-heading.selected {
  color: #cdd6f4;  /* $text - white for readability */
}

.preview-app-icon {
  min-width: 24px;
  min-height: 24px;
  opacity: 0.9;
}

.preview-app.focused .preview-app-icon {
  opacity: 1.0;
  -gtk-icon-shadow: 0 0 8px rgba(137, 180, 250, 0.6);
}

.preview-app-name {
  font-size: 10pt;
  color: $text;
}

.preview-app.focused .preview-app-name {
  color: $blue;
  font-weight: 500;
}

.preview-footer {
  margin-top: 12px;
  padding-top: 8px;
  border-top: 1px solid rgba(108, 112, 134, 0.3);  /* $overlay0 */
}

.preview-count {
  font-size: 9pt;
  color: $subtext0;
}

/* Feature 072: All Windows Preview Widget Styling (T022) */
.all-windows-preview {
  /* Inherits from .preview-card */
}

.workspace-groups-scroll {
  /* GTK scroll styling - T021: max-height 600px, smooth scrolling */
  padding: 8px 4px;
}

.workspace-groups {
  padding: 4px 0;
}

.workspace-group {
  background: rgba(49, 50, 68, 0.3);  /* $surface0 with opacity */
  padding: 8px;
  border-radius: 6px;
  border: 1px solid rgba(108, 112, 134, 0.2);  /* $overlay0 */
  transition: all 0.2s;
}

.workspace-group:hover {
  background: rgba(49, 50, 68, 0.5);
  border: 1px solid rgba(108, 112, 134, 0.4);
}

.workspace-group-header {
  margin-bottom: 6px;
  padding-bottom: 6px;
  border-bottom: 1px solid rgba(108, 112, 134, 0.2);
}

.workspace-group-number {
  font-size: 10pt;
  font-weight: 600;
  color: $blue;
}

.workspace-group-count {
  font-size: 8pt;
  color: $subtext0;
  opacity: 0.7;
}

.workspace-group-monitor {
  font-size: 8pt;
  color: $overlay0;
  opacity: 0.5;
  font-style: italic;
  /* Note: GTK CSS doesn't support margin-left: auto, use box alignment in Yuck instead */
}

.workspace-group-windows {
  padding: 0;
}

/* Reuse existing .preview-app, .preview-app-icon, .preview-app-name styles */
/* from lines 517-552 (workspace mode preview) */
'';

  # Feature 057: User Story 2 - Preview window controlled by daemon via eww open/close
  # Open workspace-preview at startup to trigger deflisten, then daemon controls open/close
  windowNames = (map (output: "workspace-bar-" + sanitize output.name) workspaceOutputs) ++ [ "workspace-preview" ];
  openCommand =
    let
      args = lib.escapeShellArgs windowNames;
    in
      ''${pkgs.eww}/bin/eww --config ${ewwConfigPath} open-many ${args}'';

in
{
  options.programs.eww-workspace-bar.enable = lib.mkEnableOption "Eww-driven workspace bar with SVG icons";

  config = lib.mkIf cfg.enable {
    # Feature 057: User Story 2 - Add workspace preview daemon (T042)
    home.packages = [ pkgs.eww workspacePanelBin workspacePreviewDaemonBin ];

    xdg.configFile."${ewwConfigDir}/eww.yuck".text = ewwYuck;
    xdg.configFile."${ewwConfigDir}/eww.scss".text = ewwScss;

    systemd.user.services.eww-workspace-bar = {
      Unit = {
        Description = "Eww workspace bar";
        After = [ "graphical-session.target" "sway-session.target" ];
        PartOf = [ "sway-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = ''${pkgs.eww}/bin/eww --config ${ewwConfigPath} daemon --no-daemonize'';
        ExecStartPost = openCommand;
        ExecStopPost = ''${pkgs.eww}/bin/eww --config ${ewwConfigPath} close-all'';
        Restart = "on-failure";
        RestartSec = 2;
        # Match Walker's XDG_DATA_DIRS for icon theme access (Papirus, Breeze, etc.)
        # Priority: curated apps → user apps → icon themes → system fallback
        Environment = [
          "XDG_DATA_DIRS=${config.home.homeDirectory}/.local/share/i3pm-applications:${config.home.homeDirectory}/.local/share:${config.home.profileDirectory}/share:/run/current-system/sw/share"
        ];
      };
      Install = {
        WantedBy = [ "sway-session.target" ];
      };
    };
  };
}
