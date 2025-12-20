{ pkgs, pythonForBackend, ... }:

let
  appCreateOpenScript = pkgs.writeShellScriptBin "app-create-open" ''
    #!${pkgs.bash}/bin/bash
    # Open application create form
    # Usage: app-create-open

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Feature 114: Enable focus mode so form inputs are clickable
    $EWW_CMD update panel_focus_mode=true

    # Clear any previous form state
    $EWW_CMD update create_app_type="regular"
    $EWW_CMD update create_app_name=""
    $EWW_CMD update create_app_display_name=""
    $EWW_CMD update create_app_command=""
    $EWW_CMD update create_app_parameters=""
    $EWW_CMD update create_app_expected_class=""
    $EWW_CMD update create_app_scope="scoped"
    $EWW_CMD update create_app_workspace="1"
    $EWW_CMD update create_app_monitor_role=""
    $EWW_CMD update create_app_icon=""
    $EWW_CMD update create_app_floating=false
    $EWW_CMD update create_app_floating_size=""
    $EWW_CMD update create_app_start_url=""
    $EWW_CMD update create_app_scope_url=""
    $EWW_CMD update create_app_error=""
    $EWW_CMD update create_app_ulid_result=""

    # Show the create form
    $EWW_CMD update app_creating=true
  '';

  # Feature 094 US8: Application create form save handler (T082)
  appCreateSaveScript = pkgs.writeShellScriptBin "app-create-save" ''
    #!${pkgs.bash}/bin/bash
    # Save application create form by reading Eww variables and calling CRUD handler
    # Usage: app-create-save

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Read form values from Eww variables
    APP_TYPE=$($EWW get create_app_type)
    NAME=$($EWW get create_app_name)
    DISPLAY_NAME=$($EWW get create_app_display_name)
    COMMAND=$($EWW get create_app_command)
    PARAMETERS=$($EWW get create_app_parameters)
    EXPECTED_CLASS=$($EWW get create_app_expected_class)
    SCOPE=$($EWW get create_app_scope)
    WORKSPACE=$($EWW get create_app_workspace)
    MONITOR_ROLE=$($EWW get create_app_monitor_role)
    ICON=$($EWW get create_app_icon)
    FLOATING=$($EWW get create_app_floating)
    FLOATING_SIZE=$($EWW get create_app_floating_size)
    START_URL=$($EWW get create_app_start_url)
    SCOPE_URL=$($EWW get create_app_scope_url)

    # Build JSON based on app type
    if [[ "$APP_TYPE" == "pwa" ]]; then
      # PWA: auto-add -pwa suffix if missing
      if [[ "$NAME" != *-pwa ]]; then
        NAME="''${NAME}-pwa"
      fi
      # Generate ULID for PWA
      ULID=$(${pkgs.bash}/bin/bash /etc/nixos/scripts/generate-ulid.sh)
      EXPECTED_CLASS="FFPWA-$ULID"

      CONFIG_JSON=$(${pkgs.jq}/bin/jq -n \
        --arg name "$NAME" \
        --arg display_name "$DISPLAY_NAME" \
        --arg command "firefoxpwa" \
        --argjson parameters '["site", "launch", "'"$ULID"'"]' \
        --arg expected_class "$EXPECTED_CLASS" \
        --arg scope "global" \
        --argjson preferred_workspace "$WORKSPACE" \
        --arg icon "$ICON" \
        --arg ulid "$ULID" \
        --arg start_url "$START_URL" \
        --arg scope_url "$SCOPE_URL" \
        '{
          name: $name,
          display_name: $display_name,
          command: $command,
          parameters: $parameters,
          expected_class: $expected_class,
          scope: $scope,
          preferred_workspace: $preferred_workspace,
          icon: $icon,
          ulid: $ulid,
          start_url: $start_url,
          scope_url: $scope_url
        }')
    elif [[ "$APP_TYPE" == "terminal" ]]; then
      # Terminal app
      # Parse parameters string to array
      PARAMS_ARRAY=$(echo "$PARAMETERS" | ${pkgs.jq}/bin/jq -R 'split(" ") | map(select(. != ""))')

      CONFIG_JSON=$(${pkgs.jq}/bin/jq -n \
        --arg name "$NAME" \
        --arg display_name "$DISPLAY_NAME" \
        --arg command "$COMMAND" \
        --argjson parameters "$PARAMS_ARRAY" \
        --arg expected_class "$EXPECTED_CLASS" \
        --arg scope "$SCOPE" \
        --argjson preferred_workspace "$WORKSPACE" \
        --arg monitor_role "$MONITOR_ROLE" \
        --arg icon "$ICON" \
        --argjson floating "$FLOATING" \
        --arg floating_size "$FLOATING_SIZE" \
        --argjson terminal true \
        '{
          name: $name,
          display_name: $display_name,
          command: $command,
          parameters: $parameters,
          expected_class: $expected_class,
          scope: $scope,
          preferred_workspace: $preferred_workspace,
          icon: $icon,
          floating: $floating,
          terminal: $terminal
        } | if $monitor_role != "" then . + {preferred_monitor_role: $monitor_role} else . end
          | if $floating and $floating_size != "" then . + {floating_size: $floating_size} else . end')
    else
      # Regular app
      PARAMS_ARRAY=$(echo "$PARAMETERS" | ${pkgs.jq}/bin/jq -R 'split(" ") | map(select(. != ""))')

      CONFIG_JSON=$(${pkgs.jq}/bin/jq -n \
        --arg name "$NAME" \
        --arg display_name "$DISPLAY_NAME" \
        --arg command "$COMMAND" \
        --argjson parameters "$PARAMS_ARRAY" \
        --arg expected_class "$EXPECTED_CLASS" \
        --arg scope "$SCOPE" \
        --argjson preferred_workspace "$WORKSPACE" \
        --arg monitor_role "$MONITOR_ROLE" \
        --arg icon "$ICON" \
        --argjson floating "$FLOATING" \
        --arg floating_size "$FLOATING_SIZE" \
        '{
          name: $name,
          display_name: $display_name,
          command: $command,
          parameters: $parameters,
          expected_class: $expected_class,
          scope: $scope,
          preferred_workspace: $preferred_workspace,
          icon: $icon,
          floating: $floating
        } | if $monitor_role != "" then . + {preferred_monitor_role: $monitor_role} else . end
          | if $floating and $floating_size != "" then . + {floating_size: $floating_size} else . end')
    fi

    # Call the CRUD handler
    export PYTHONPATH="${../../../tools}"
    REQUEST_JSON=$(${pkgs.jq}/bin/jq -n \
      --arg action "create_app" \
      --argjson config "$CONFIG_JSON" \
      '{action: $action, config: $config}')

    RESULT=$(echo "$REQUEST_JSON" | ${pythonForBackend}/bin/python3 -c "
import sys
import json
import asyncio
sys.path.insert(0, '${../../../tools}')
sys.path.insert(0, '${../../../tools/monitoring-panel}')
from app_crud_handler import AppCRUDHandler

handler = AppCRUDHandler()
request = json.loads(sys.stdin.read())
result = asyncio.run(handler.handle_request(request))
print(json.dumps(result))
")

    # Check result
    SUCCESS=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.success')
    if [[ "$SUCCESS" == "true" ]]; then
      # Success: clear form state and refresh
      # Feature 114: Disable focus mode to return to click-through
      $EWW update panel_focus_mode=false
      $EWW update app_creating=false
      $EWW update create_app_type="regular"
      $EWW update create_app_name=""
      $EWW update create_app_display_name=""
      $EWW update create_app_command=""
      $EWW update create_app_parameters=""
      $EWW update create_app_expected_class=""
      $EWW update create_app_scope="scoped"
      $EWW update create_app_workspace="1"
      $EWW update create_app_monitor_role=""
      $EWW update create_app_icon=""
      $EWW update create_app_floating=false
      $EWW update create_app_floating_size=""
      $EWW update create_app_start_url=""
      $EWW update create_app_scope_url=""
      $EWW update create_app_error=""

      # If PWA, show generated ULID
      if [[ "$APP_TYPE" == "pwa" ]]; then
        ULID=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.ulid // empty')
        if [[ -n "$ULID" ]]; then
          $EWW update create_app_ulid_result="$ULID"
        fi
      fi

      # Refresh apps data
      APPS_DATA=$(${pythonForBackend}/bin/python3 ${../../../tools/i3_project_manager/cli/monitoring_data.py} --mode apps)
      $EWW update apps_data="$APPS_DATA"

      echo "Application created successfully: $NAME"
    else
      # Show error message
      ERROR_MSG=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.error_message')
      VALIDATION_ERRORS=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.validation_errors | join(", ")')
      if [[ -n "$VALIDATION_ERRORS" && "$VALIDATION_ERRORS" != "null" ]]; then
        $EWW update create_app_error="$VALIDATION_ERRORS"
      else
        $EWW update create_app_error="$ERROR_MSG"
      fi
      echo "Error creating application: $ERROR_MSG" >&2
      exit 1
    fi
  '';

  # Feature 094 US8: Application create form cancel handler (T076)
  appCreateCancelScript = pkgs.writeShellScriptBin "app-create-cancel" ''
    #!${pkgs.bash}/bin/bash
    # Cancel application create form
    # Usage: app-create-cancel

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Feature 114: Disable focus mode to return to click-through
    $EWW update panel_focus_mode=false

    # Hide form and clear all fields
    $EWW update app_creating=false
    $EWW update create_app_type="regular"
    $EWW update create_app_name=""
    $EWW update create_app_display_name=""
    $EWW update create_app_command=""
    $EWW update create_app_parameters=""
    $EWW update create_app_expected_class=""
    $EWW update create_app_scope="scoped"
    $EWW update create_app_workspace="1"
    $EWW update create_app_monitor_role=""
    $EWW update create_app_icon=""
    $EWW update create_app_floating=false
    $EWW update create_app_floating_size=""
    $EWW update create_app_start_url=""
    $EWW update create_app_scope_url=""
    $EWW update create_app_error=""
    $EWW update create_app_ulid_result=""
  '';

  appDeleteOpenScript = pkgs.writeShellScriptBin "app-delete-open" ''
    #!${pkgs.bash}/bin/bash
    # Open application delete confirmation dialog
    # Usage: app-delete-open <app_name> <display_name> [is_pwa] [ulid]

    set -euo pipefail

    APP_NAME="''${1:-}"
    DISPLAY_NAME="''${2:-}"
    IS_PWA="''${3:-false}"
    ULID="''${4:-}"

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    if [[ -z "$APP_NAME" ]]; then
      echo "Error: App name required" >&2
      exit 1
    fi

    # Clear previous state
    $EWW update delete_app_error=""

    # Set dialog state
    $EWW update delete_app_name="$APP_NAME"
    $EWW update delete_app_display_name="''${DISPLAY_NAME:-$APP_NAME}"
    $EWW update delete_app_is_pwa="$IS_PWA"
    $EWW update delete_app_ulid="$ULID"
    $EWW update app_deleting=true
  '';

  # Feature 094 US9: Application delete confirm handler (T094)
  appDeleteConfirmScript = pkgs.writeShellScriptBin "app-delete-confirm" ''
    #!${pkgs.bash}/bin/bash
    # Execute application deletion via CRUD handler
    # Usage: app-delete-confirm

    set -euo pipefail

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Read deletion parameters
    APP_NAME=$($EWW get delete_app_name)

    if [[ -z "$APP_NAME" ]]; then
      $EWW update delete_app_error="No application selected for deletion"
      exit 1
    fi

    # Build request JSON
    REQUEST=$(${pkgs.jq}/bin/jq -n \
      --arg name "$APP_NAME" \
      '{"action": "delete_app", "app_name": $name}')

    echo "Deleting application: $APP_NAME" >&2

    # Call the CRUD handler
    export PYTHONPATH="${../../../tools}:${../../../tools/monitoring-panel}"
    RESULT=$(echo "$REQUEST" | ${pythonForBackend}/bin/python3 -c "
import sys
sys.path.insert(0, '${../../../tools}')
sys.path.insert(0, '${../../../tools/monitoring-panel}')
from app_crud_handler import AppCRUDHandler
import asyncio
import json

handler = AppCRUDHandler()
request = json.loads(sys.stdin.read())
result = asyncio.run(handler.handle_request(request))
print(json.dumps(result))
")

    # Check result
    SUCCESS=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.success')

    if [[ "$SUCCESS" == "true" ]]; then
      # Check for PWA warning
      PWA_WARNING=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.pwa_warning // empty')

      # Success - close dialog
      $EWW update app_deleting=false
      $EWW update delete_app_name=""
      $EWW update delete_app_display_name=""
      $EWW update delete_app_is_pwa=false
      $EWW update delete_app_ulid=""
      $EWW update delete_app_error=""

      # Refresh apps data
      APPS_DATA=$(${pythonForBackend}/bin/python3 ${../../../tools/i3_project_manager/cli/monitoring_data.py} --mode apps)
      $EWW update apps_data="$APPS_DATA"

      # Show notification with PWA warning if applicable
      if [[ -n "$PWA_WARNING" ]]; then
        ${pkgs.libnotify}/bin/notify-send -t 8000 "Application Deleted" "$APP_NAME deleted. Note: $PWA_WARNING"
      else
        ${pkgs.libnotify}/bin/notify-send -t 3000 "Application Deleted" "$APP_NAME has been deleted. Rebuild required."
      fi

      echo "Application deleted successfully: $APP_NAME"
    else
      # Show error in dialog
      ERROR_MSG=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.error_message')
      $EWW update delete_app_error="$ERROR_MSG"
      echo "Error deleting application: $ERROR_MSG" >&2
      exit 1
    fi
  '';

  appDeleteCancelScript = pkgs.writeShellScriptBin "app-delete-cancel" ''
    #!${pkgs.bash}/bin/bash
    # Cancel application delete confirmation dialog
    # Usage: app-delete-cancel

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Hide dialog and clear state
    $EWW update app_deleting=false
    $EWW update delete_app_name=""
    $EWW update delete_app_display_name=""
    $EWW update delete_app_is_pwa=false
    $EWW update delete_app_ulid=""
    $EWW update delete_app_error=""
  '';

  # Feature 093: Focus window action script (T009-T015)

in
{
  inherit appCreateOpenScript appCreateSaveScript appCreateCancelScript
          appDeleteOpenScript appDeleteConfirmScript appDeleteCancelScript;
}
