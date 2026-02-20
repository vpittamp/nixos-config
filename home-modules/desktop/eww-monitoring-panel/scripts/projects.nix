{ pkgs, pythonForBackend, ... }:

let
  projectCrudScript = pkgs.writeShellScriptBin "project-crud-handler" ''
    #!${pkgs.bash}/bin/bash
    # Set PYTHONPATH to tools directory for i3_project_manager imports
    export PYTHONPATH="${../../../tools}"

    # Use Python with Pydantic and other dependencies
    exec ${pythonForBackend}/bin/python3 -m i3_project_manager.cli.project_crud_handler "$@"
  '';

  # Feature 094: Project edit form opener (T038)
  projectEditOpenScript = pkgs.writeShellScriptBin "project-edit-open" ''
    #!${pkgs.bash}/bin/bash
    # Open edit form by loading project data into eww variables
    # Usage: project-edit-open <name> <display_name> <icon> <directory> <scope> <remote_enabled> <remote_host> <remote_user> <remote_dir> <remote_port>

    NAME="$1"
    DISPLAY_NAME="$2"
    ICON="$3"
    DIRECTORY="$4"
    SCOPE="$5"
    REMOTE_ENABLED="$6"
    REMOTE_HOST="$7"
    REMOTE_USER="$8"
    REMOTE_DIR="$9"
    REMOTE_PORT="''${10}"

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Feature 114: Enable focus mode so form inputs are clickable
    $EWW_CMD update panel_focus_mode=true

    # Update all eww variables
    $EWW_CMD update editing_project_name="$NAME"
    $EWW_CMD update edit_form_display_name="$DISPLAY_NAME"
    $EWW_CMD update edit_form_icon="$ICON"
    $EWW_CMD update edit_form_directory="$DIRECTORY"
    $EWW_CMD update edit_form_scope="$SCOPE"
    $EWW_CMD update edit_form_remote_enabled="$REMOTE_ENABLED"
    $EWW_CMD update edit_form_remote_host="$REMOTE_HOST"
    $EWW_CMD update edit_form_remote_user="$REMOTE_USER"
    $EWW_CMD update edit_form_remote_dir="$REMOTE_DIR"
    $EWW_CMD update edit_form_remote_port="$REMOTE_PORT"
    $EWW_CMD update edit_form_error=""
  '';

  # Feature 094: Project edit form save handler (T038)
  projectEditSaveScript = pkgs.writeShellScriptBin "project-edit-save" ''
    #!${pkgs.bash}/bin/bash
    # Save project edit form by reading Eww variables and calling CRUD handler
    # Usage: project-edit-save [project-name]
    # If no project-name is provided, reads from editing_project_name eww variable

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Get project name from argument or from eww variable
    if [ -n "$1" ]; then
      PROJECT_NAME="$1"
    else
      PROJECT_NAME=$($EWW get editing_project_name)
    fi

    # Validate project name
    if [ -z "$PROJECT_NAME" ]; then
      echo "Error: No project name provided" >&2
      $EWW update edit_form_error="No project selected"
      exit 1
    fi

    # Feature 096 T022: Set loading state to prevent double-submit
    $EWW update save_in_progress=true

    # Read form values from Eww variables
    DISPLAY_NAME=$($EWW get edit_form_display_name)
    ICON=$($EWW get edit_form_icon)
    SCOPE=$($EWW get edit_form_scope)
    REMOTE_ENABLED=$($EWW get edit_form_remote_enabled)
    REMOTE_HOST=$($EWW get edit_form_remote_host)
    REMOTE_USER=$($EWW get edit_form_remote_user)
    REMOTE_DIR=$($EWW get edit_form_remote_dir)
    REMOTE_PORT=$($EWW get edit_form_remote_port)

    # Build JSON update object (using printf to avoid quote issues)
    UPDATES=$(printf '%s\n' "{" \
      "  \"display_name\": \"$DISPLAY_NAME\"," \
      "  \"icon\": \"$ICON\"," \
      "  \"scope\": \"$SCOPE\"," \
      "  \"remote\": {" \
      "    \"enabled\": $REMOTE_ENABLED," \
      "    \"host\": \"$REMOTE_HOST\"," \
      "    \"user\": \"$REMOTE_USER\"," \
      "    \"remote_dir\": \"$REMOTE_DIR\"," \
      "    \"port\": $REMOTE_PORT" \
      "  }" \
      "}")

    # Call CRUD handler
    export PYTHONPATH="${../../../tools}"
    RESULT=$(${pythonForBackend}/bin/python3 -m i3_project_manager.cli.project_crud_handler edit "$PROJECT_NAME" --updates "$UPDATES")

    # Feature 094 T041: Check for save success and conflicts
    STATUS=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.status')
    CONFLICT=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.conflict // false')

    if [ "$STATUS" = "success" ]; then
      # Feature 096 T010: Handle conflicts as warnings, not errors
      # The save DID succeed (last write wins), so continue with success handling
      # but show a warning notification to inform the user about the conflict
      if [ "$CONFLICT" = "true" ]; then
        # Feature 096 T023: Show warning notification for conflicts (but save succeeded)
        $EWW update warning_notification="File was modified externally - your changes were saved (last write wins)"
        $EWW update warning_notification_visible=true
        # Auto-dismiss warning after 5 seconds
        (sleep 5 && $EWW update warning_notification_visible=false warning_notification="") &
        echo "Warning: File was modified externally but your changes were saved (last write wins)" >&2
      fi

      # Success: Clear editing state and refresh
      # Feature 114: Disable focus mode to return to click-through
      $EWW update panel_focus_mode=false
      $EWW update editing_project_name='''
      $EWW update edit_form_error='''

      # Note: Project list will be refreshed by the deflisten stream automatically

      # Feature 096 T023: Show success notification
      $EWW update success_notification="Project saved successfully"
      $EWW update success_notification_visible=true
      # Auto-dismiss after 3 seconds (T020)
      (sleep 3 && $EWW update success_notification_visible=false success_notification="") &

      # Feature 096 T022: Clear loading state
      $EWW update save_in_progress=false

      echo "Project saved successfully"
    else
      # Feature 096 T024: Show error notification with specific message
      ERROR=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.error')
      VALIDATION_ERRORS=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.validation_errors // [] | length')

      if [ "$VALIDATION_ERRORS" -gt 0 ]; then
        # Extract first validation error for display
        FIRST_ERROR=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.validation_errors[0].message')
        ERROR_MSG="Validation error: $FIRST_ERROR"
      else
        ERROR_MSG="$ERROR"
      fi

      # Show error in form AND as notification toast
      $EWW update edit_form_error="$ERROR_MSG"
      $EWW update error_notification="$ERROR_MSG"
      $EWW update error_notification_visible=true
      # Error notifications persist until dismissed (no auto-dismiss)

      # Feature 096 T022: Clear loading state
      $EWW update save_in_progress=false

      echo "Error: $ERROR_MSG" >&2
      exit 1
    fi
  '';

  # Feature 094 T040: Conflict resolution handler script
  # Handles user choice when file conflicts are detected
  projectConflictResolveScript = pkgs.writeShellScriptBin "project-conflict-resolve" ''
    #!${pkgs.bash}/bin/bash
    # Feature 094 T040: Resolve file conflicts during save
    # Usage: project-conflict-resolve <action> <project-name>
    #   action: keep-file | keep-ui | merge-manual

    ACTION="$1"
    PROJECT_NAME="$2"
    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    case "$ACTION" in
      keep-file)
        # Discard UI changes, reload from file
        # Close edit form and conflict dialog
        # Feature 114: Disable focus mode to return to click-through
        $EWW_CMD update panel_focus_mode=false
        $EWW_CMD update conflict_dialog_visible=false
        $EWW_CMD update editing_project_name='''
        $EWW_CMD update edit_form_error='''
        # Note: Project list will be refreshed by the deflisten stream automatically
        echo "Kept file changes for project: $PROJECT_NAME" >&2
        ;;

      keep-ui)
        # Force overwrite file with UI changes (ignoring mtime conflict)
        # Re-run save with force flag
        # For now, just retry the save (which will fail again if conflict persists)
        # TODO: Implement force-save in project_crud_handler
        $EWW_CMD update conflict_dialog_visible=false
        echo "Force-saving UI changes for project: $PROJECT_NAME" >&2
        project-edit-save "$PROJECT_NAME"
        ;;

      merge-manual)
        # Feature 101: Open repos.json for manual editing
        # Individual project files no longer exist - all data is in repos.json
        REPOS_FILE="$HOME/.config/i3/repos.json"
        if [ -f "$REPOS_FILE" ]; then
          # Use default editor or fallback to nano
          ''${EDITOR:-nano} "$REPOS_FILE"
          # Close dialog - project list will be refreshed by the deflisten stream automatically
          # Feature 114: Disable focus mode to return to click-through
          $EWW_CMD update panel_focus_mode=false
          $EWW_CMD update conflict_dialog_visible=false
          $EWW_CMD update editing_project_name='''
          # Trigger rediscovery to ensure state is consistent
          i3pm discover >/dev/null 2>&1 || true
          echo "Opened $REPOS_FILE for manual editing (project: $PROJECT_NAME)" >&2
        else
          echo "Error: repos.json not found" >&2
          exit 1
        fi
        ;;

      *)
        echo "Error: Invalid action: $ACTION" >&2
        echo "Usage: project-conflict-resolve <keep-file|keep-ui|merge-manual> <project-name>" >&2
        exit 1
        ;;
    esac
  '';

  # Feature 094 T039: Form validation stream script (300ms debouncing)
  # Monitors Eww form variables and streams validation results via deflisten
  formValidationStreamScript = pkgs.writeShellScriptBin "form-validation-stream" ''
    #!${pkgs.bash}/bin/bash
    # Feature 094 T039: Real-time form validation with 300ms debouncing

    # Set PYTHONPATH to tools directory for i3_project_manager imports
    export PYTHONPATH="${../../../tools}:${../../../tools/monitoring-panel}"

    # Run validation stream (reads Eww variables, outputs JSON to stdout)
    exec ${pythonForBackend}/bin/python3 -c "
import sys
sys.path.insert(0, '${../../../tools}')
sys.path.insert(0, '${../../../tools/monitoring-panel}')
from project_form_validator_stream import FormValidationStream
import asyncio
stream = FormValidationStream('$HOME/.config/eww-monitoring-panel')
asyncio.run(stream.run())
"
  '';

  # Feature 099 T021: Worktree create form opener
  worktreeCreateOpenScript = pkgs.writeShellScriptBin "worktree-create-open" ''
    #!${pkgs.bash}/bin/bash
    # Open worktree create form for a given parent project
    # Usage: worktree-create-open <parent_project_name>
    # Feature 102: Auto-populate fields and suggest next branch number

    PARENT_PROJECT="$1"
    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    if [[ -z "$PARENT_PROJECT" ]]; then
      echo "Usage: worktree-create-open <parent_project_name>" >&2
      exit 1
    fi

    # Feature 102: Get repo path from repos.json
    REPOS_FILE="$HOME/.config/i3/repos.json"
    REPO_PATH=""
    DEFAULT_BRANCH="main"
    REMOTE_ENABLED="false"
    REMOTE_HOST="ryzen"
    REMOTE_USER="''${USER:-vpittamp}"
    REMOTE_PORT="22"
    REMOTE_BASE=""

    if [[ -f "$REPOS_FILE" ]]; then
      # Parse qualified name: account/repo
      REPO_ACCOUNT=$(echo "$PARENT_PROJECT" | cut -d'/' -f1)
      REPO_NAME=$(echo "$PARENT_PROJECT" | cut -d'/' -f2)

      # Get repo path for auto-populating worktree path
      REPO_PATH=$(${pkgs.jq}/bin/jq -r --arg acc "$REPO_ACCOUNT" --arg name "$REPO_NAME" \
        '.repositories[] | select(.account == $acc and .name == $name) | .path // empty' "$REPOS_FILE")
      DEFAULT_BRANCH=$(${pkgs.jq}/bin/jq -r --arg acc "$REPO_ACCOUNT" --arg name "$REPO_NAME" \
        '.repositories[] | select(.account == $acc and .name == $name) | .default_branch // "main"' "$REPOS_FILE")
    fi

    # If this repository already has any remote worktree profile, inherit those defaults.
    REMOTE_PROFILES_FILE="$HOME/.config/i3/worktree-remote-profiles.json"
    if [[ -f "$REMOTE_PROFILES_FILE" ]]; then
      PROFILE_MATCH=$(${pkgs.jq}/bin/jq -c --arg prefix "$PARENT_PROJECT:" '
        (.profiles // {})
        | to_entries
        | map(select((.key | startswith($prefix)) and ((.value.enabled // true) == true)))
        | .[0] // empty
      ' "$REMOTE_PROFILES_FILE")

      if [[ -n "$PROFILE_MATCH" ]]; then
        REMOTE_ENABLED="true"
        REMOTE_HOST=$(echo "$PROFILE_MATCH" | ${pkgs.jq}/bin/jq -r '.value.host // "ryzen"')
        REMOTE_USER=$(echo "$PROFILE_MATCH" | ${pkgs.jq}/bin/jq -r '.value.user // env.USER // "vpittamp"')
        REMOTE_PORT=$(echo "$PROFILE_MATCH" | ${pkgs.jq}/bin/jq -r '.value.port // 22')
        PROFILE_BRANCH=$(echo "$PROFILE_MATCH" | ${pkgs.jq}/bin/jq -r '.key | split(":")[1] // ""')
        PROFILE_REMOTE_DIR=$(echo "$PROFILE_MATCH" | ${pkgs.jq}/bin/jq -r '.value.remote_dir // .value.working_dir // ""')

        if [[ -n "$PROFILE_REMOTE_DIR" ]]; then
          if [[ -n "$PROFILE_BRANCH" ]] && [[ "$PROFILE_REMOTE_DIR" == */"$PROFILE_BRANCH" ]]; then
            REMOTE_BASE="''${PROFILE_REMOTE_DIR%/$PROFILE_BRANCH}"
          else
            REMOTE_BASE="$PROFILE_REMOTE_DIR"
          fi
        fi
      fi
    fi

    # Clear form fields and set parent project
    # Feature 114: Enable focus mode so form inputs are clickable
    $EWW_CMD update panel_focus_mode=true
    $EWW_CMD update worktree_creating=true
    $EWW_CMD update worktree_form_parent_project="$PARENT_PROJECT"
    $EWW_CMD update edit_form_icon="🌿"
    $EWW_CMD update edit_form_error=""

    # Feature 102: Store repo path for path auto-generation and description-to-branch conversion
    $EWW_CMD update worktree_form_repo_path="$REPO_PATH"

    # Clear fields - user enters description, branch name auto-generated
    $EWW_CMD update worktree_form_branch_name=""
    $EWW_CMD update worktree_form_base_branch="$DEFAULT_BRANCH"
    $EWW_CMD update worktree_form_description=""
    $EWW_CMD update worktree_form_path=""
    $EWW_CMD update worktree_form_remote_enabled="$REMOTE_ENABLED"
    $EWW_CMD update worktree_form_remote_host="$REMOTE_HOST"
    $EWW_CMD update worktree_form_remote_user="$REMOTE_USER"
    $EWW_CMD update worktree_form_remote_port="$REMOTE_PORT"
    $EWW_CMD update worktree_form_remote_base="$REMOTE_BASE"
    $EWW_CMD update worktree_form_remote_dir=""
    $EWW_CMD update edit_form_display_name=""

    # Also expand the parent project to show the form in context
    CURRENT=$($EWW_CMD get expanded_projects)
    if ! echo "$CURRENT" | ${pkgs.jq}/bin/jq -e "index(\"$PARENT_PROJECT\")" > /dev/null 2>&1; then
      NEW=$(echo "$CURRENT" | ${pkgs.jq}/bin/jq -c ". + [\"$PARENT_PROJECT\"]")
      $EWW_CMD update "expanded_projects=$NEW"
    fi
  '';

  # Feature 102: Auto-populate worktree form fields based on description
  # Uses legacy branch naming heuristics to generate a useful branch suggestion
  worktreeAutoPopulateScript = pkgs.writeShellScriptBin "worktree-auto-populate" ''
    #!${pkgs.bash}/bin/bash
    # Auto-populate worktree form fields when description changes
    # Usage: worktree-auto-populate <description>

    DESCRIPTION="$1"
    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    if [[ -z "$DESCRIPTION" ]]; then
      exit 0
    fi

    # Get stored repo path and parent project
    REPO_PATH=$($EWW_CMD get worktree_form_repo_path 2>/dev/null || echo "")
    PARENT_PROJECT=$($EWW_CMD get worktree_form_parent_project 2>/dev/null || echo "")

    # Feature 143: Fallback to repos.json lookup if repo_path is empty (race condition fix)
    # This handles the case where auto-populate runs before worktree-create-open finishes
    if [[ -z "$REPO_PATH" && -n "$PARENT_PROJECT" ]]; then
      REPOS_FILE="$HOME/.config/i3/repos.json"
      if [[ -f "$REPOS_FILE" ]]; then
        REPO_ACCOUNT=$(echo "$PARENT_PROJECT" | cut -d'/' -f1)
        REPO_NAME=$(echo "$PARENT_PROJECT" | cut -d'/' -f2)
        REPO_PATH=$(${pkgs.jq}/bin/jq -r --arg acc "$REPO_ACCOUNT" --arg name "$REPO_NAME" \
          '.repositories[] | select(.account == $acc and .name == $name) | .path // empty' "$REPOS_FILE")
        # Also update the EWW variable so subsequent calls don't need to look it up
        if [[ -n "$REPO_PATH" ]]; then
          $EWW_CMD update "worktree_form_repo_path=$REPO_PATH"
        fi
      fi
    fi

    # Function to generate branch suffix from description (same logic as create-new-feature.sh)
    generate_branch_suffix() {
      local description="$1"

      # Common stop words to filter out
      local stop_words="^(i|a|an|the|to|for|of|in|on|at|by|with|from|is|are|was|were|be|been|being|have|has|had|do|does|did|will|would|should|could|can|may|might|must|shall|this|that|these|those|my|your|our|their|want|need|add|get|set)$"

      # Convert to lowercase and split into words
      local clean_name=$(echo "$description" | tr '[:upper:]' '[:lower:]' | ${pkgs.gnused}/bin/sed 's/[^a-z0-9]/ /g')

      # Filter words: remove stop words and words shorter than 3 chars
      local meaningful_words=()
      for word in $clean_name; do
        [ -z "$word" ] && continue
        if ! echo "$word" | ${pkgs.gnugrep}/bin/grep -qiE "$stop_words"; then
          if [ ''${#word} -ge 3 ]; then
            meaningful_words+=("$word")
          fi
        fi
      done

      # Use first 3-4 meaningful words
      if [ ''${#meaningful_words[@]} -gt 0 ]; then
        local max_words=3
        if [ ''${#meaningful_words[@]} -eq 4 ]; then max_words=4; fi

        local result=""
        local count=0
        for word in "''${meaningful_words[@]}"; do
          if [ $count -ge $max_words ]; then break; fi
          if [ -n "$result" ]; then result="$result-"; fi
          result="$result$word"
          count=$((count + 1))
        done
        echo "$result"
      else
        # Fallback
        echo "$description" | tr '[:upper:]' '[:lower:]' | ${pkgs.gnused}/bin/sed 's/[^a-z0-9]/-/g' | ${pkgs.gnused}/bin/sed 's/-\+/-/g' | ${pkgs.gnused}/bin/sed 's/^-//' | ${pkgs.gnused}/bin/sed 's/-$//' | tr '-' '\n' | ${pkgs.gnugrep}/bin/grep -v '^$' | head -3 | tr '\n' '-' | ${pkgs.gnused}/bin/sed 's/-$//'
      fi
    }

    # Get next branch number from repos.json
    get_next_branch_number() {
      local repo_path="$1"
      local parent_project="$2"
      local repos_file="$HOME/.config/i3/repos.json"

      if [[ ! -f "$repos_file" ]]; then
        echo "100"
        return
      fi

      local repo_account=$(echo "$parent_project" | cut -d'/' -f1)
      local repo_name=$(echo "$parent_project" | cut -d'/' -f2)

      # Get max branch number from existing worktrees
      local max_number=$(${pkgs.jq}/bin/jq -r --arg acc "$repo_account" --arg name "$repo_name" \
        '.repositories[] | select(.account == $acc and .name == $name) | .worktrees[]?.branch // empty' "$repos_file" \
        | ${pkgs.gnugrep}/bin/grep -oE '^[0-9]+' | sort -n | tail -1)

      # Also check local branches in the repo
      if [[ -n "$repo_path" && -d "$repo_path" ]]; then
        local local_max=$(cd "$repo_path" && git branch 2>/dev/null | ${pkgs.gnugrep}/bin/grep -oE '^[* ]*[0-9]+' | ${pkgs.gnused}/bin/sed 's/[* ]*//' | sort -n | tail -1)
        if [[ -n "$local_max" && "$local_max" -gt "''${max_number:-0}" ]]; then
          max_number="$local_max"
        fi
      fi

      if [[ -n "$max_number" ]]; then
        echo $((max_number + 1))
      else
        echo "100"
      fi
    }

    # Generate branch suffix from description
    BRANCH_SUFFIX=$(generate_branch_suffix "$DESCRIPTION")

    # Get next available branch number
    NEXT_NUMBER=$(get_next_branch_number "$REPO_PATH" "$PARENT_PROJECT")
    FEATURE_NUM=$(printf "%03d" "$NEXT_NUMBER")

    # Construct full branch name
    BRANCH_NAME="''${FEATURE_NUM}-''${BRANCH_SUFFIX}"

    # Update branch name field
    $EWW_CMD update "worktree_form_branch_name=$BRANCH_NAME"

    # Auto-generate worktree path: <repo_path>/<branch_name>
    if [[ -n "$REPO_PATH" && -n "$BRANCH_NAME" ]]; then
      WORKTREE_PATH="''${REPO_PATH}/''${BRANCH_NAME}"
      $EWW_CMD update "worktree_form_path=$WORKTREE_PATH"
    fi

    # Auto-generate remote directory when remote profile is enabled.
    REMOTE_ENABLED=$($EWW_CMD get worktree_form_remote_enabled 2>/dev/null || echo "false")
    REMOTE_BASE=$($EWW_CMD get worktree_form_remote_base 2>/dev/null || echo "")
    if [[ "$REMOTE_ENABLED" == "true" ]] && [[ -n "$BRANCH_NAME" ]]; then
      if [[ -n "$REMOTE_BASE" ]]; then
        REMOTE_DIR="''${REMOTE_BASE}/''${BRANCH_NAME}"
      elif [[ -n "$WORKTREE_PATH" ]]; then
        REMOTE_DIR="$WORKTREE_PATH"
      else
        REMOTE_DIR=""
      fi
      if [[ -n "$REMOTE_DIR" ]]; then
        $EWW_CMD update "worktree_form_remote_dir=$REMOTE_DIR"
      fi
    fi

    # Auto-generate display name: NNN - Description (Title Case of original)
    TITLE_CASE=$(echo "$DESCRIPTION" | ${pkgs.gnused}/bin/sed 's/\b\(.\)/\u\1/g')
    DISPLAY_NAME="$FEATURE_NUM - $TITLE_CASE"
    $EWW_CMD update "edit_form_display_name=$DISPLAY_NAME"
  '';

  # Feature 142: Update worktree path when branch name changes manually
  worktreeUpdatePathScript = pkgs.writeShellScriptBin "worktree-update-path" ''
    #!${pkgs.bash}/bin/bash
    # Update worktree path when branch name changes
    # Usage: worktree-update-path <branch_name>

    BRANCH_NAME="$1"
    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    if [[ -z "$BRANCH_NAME" ]]; then
      exit 0
    fi

    # Get stored repo path and parent project
    REPO_PATH=$($EWW_CMD get worktree_form_repo_path 2>/dev/null || echo "")
    PARENT_PROJECT=$($EWW_CMD get worktree_form_parent_project 2>/dev/null || echo "")

    # Feature 143: Fallback to repos.json lookup if repo_path is empty (race condition fix)
    if [[ -z "$REPO_PATH" && -n "$PARENT_PROJECT" ]]; then
      REPOS_FILE="$HOME/.config/i3/repos.json"
      if [[ -f "$REPOS_FILE" ]]; then
        REPO_ACCOUNT=$(echo "$PARENT_PROJECT" | cut -d'/' -f1)
        REPO_NAME=$(echo "$PARENT_PROJECT" | cut -d'/' -f2)
        REPO_PATH=$(${pkgs.jq}/bin/jq -r --arg acc "$REPO_ACCOUNT" --arg name "$REPO_NAME" \
          '.repositories[] | select(.account == $acc and .name == $name) | .path // empty' "$REPOS_FILE")
        if [[ -n "$REPO_PATH" ]]; then
          $EWW_CMD update "worktree_form_repo_path=$REPO_PATH"
        fi
      fi
    fi

    # Auto-generate worktree path: <repo_path>/<branch_name>
    if [[ -n "$REPO_PATH" ]]; then
      WORKTREE_PATH="''${REPO_PATH}/''${BRANCH_NAME}"
      $EWW_CMD update "worktree_form_path=$WORKTREE_PATH"

      # Keep remote directory in sync for SSH worktree mode.
      REMOTE_ENABLED=$($EWW_CMD get worktree_form_remote_enabled 2>/dev/null || echo "false")
      REMOTE_BASE=$($EWW_CMD get worktree_form_remote_base 2>/dev/null || echo "")
      if [[ "$REMOTE_ENABLED" == "true" ]]; then
        if [[ -n "$REMOTE_BASE" ]]; then
          REMOTE_DIR="''${REMOTE_BASE}/''${BRANCH_NAME}"
        else
          REMOTE_DIR="$WORKTREE_PATH"
        fi
        $EWW_CMD update "worktree_form_remote_dir=$REMOTE_DIR"
      fi
    fi
  '';

  # Feature 102: Open worktree delete confirmation dialog
  worktreeDeleteOpenScript = pkgs.writeShellScriptBin "worktree-delete-open" ''
    #!${pkgs.bash}/bin/bash
    # Open worktree delete confirmation dialog
    # Usage: worktree-delete-open <qualified_name> <branch_name> <is_dirty>

    QUALIFIED_NAME="$1"
    BRANCH_NAME="$2"
    IS_DIRTY="$3"

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    if [[ -z "$QUALIFIED_NAME" ]]; then
      echo "Usage: worktree-delete-open <qualified_name> <branch_name> <is_dirty>" >&2
      exit 1
    fi

    # Set dialog state
    $EWW_CMD update worktree_delete_name="$QUALIFIED_NAME"
    $EWW_CMD update worktree_delete_branch="$BRANCH_NAME"
    $EWW_CMD update worktree_delete_is_dirty="$IS_DIRTY"
    $EWW_CMD update worktree_delete_dialog_visible=true
  '';

  # Feature 102: Confirm and execute worktree deletion
  worktreeDeleteConfirmScript = pkgs.writeShellScriptBin "worktree-delete-confirm" ''
    #!${pkgs.bash}/bin/bash
    # Execute worktree deletion after confirmation
    # Usage: worktree-delete-confirm

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Get worktree to delete from dialog state
    QUALIFIED_NAME=$($EWW_CMD get worktree_delete_name)

    if [[ -z "$QUALIFIED_NAME" ]]; then
      echo "No worktree selected for deletion" >&2
      exit 1
    fi

    # Parse qualified name: account/repo:branch
    # e.g., vpittamp/nixos-config:101-worktree-click-switch
    REPO_QUALIFIED=$(echo "$QUALIFIED_NAME" | cut -d':' -f1)
    BRANCH_NAME=$(echo "$QUALIFIED_NAME" | cut -d':' -f2)
    REPO_ACCOUNT=$(echo "$REPO_QUALIFIED" | cut -d'/' -f1)
    REPO_NAME=$(echo "$REPO_QUALIFIED" | cut -d'/' -f2)

    # Get repo path from repos.json
    REPOS_FILE="$HOME/.config/i3/repos.json"
    if [[ ! -f "$REPOS_FILE" ]]; then
      $EWW_CMD update error_notification="repos.json not found"
      $EWW_CMD update error_notification_visible=true
      $EWW_CMD update worktree_delete_dialog_visible=false
      exit 1
    fi

    REPO_PATH=$(${pkgs.jq}/bin/jq -r --arg acc "$REPO_ACCOUNT" --arg name "$REPO_NAME" \
      '.repositories[] | select(.account == $acc and .name == $name) | .path // empty' "$REPOS_FILE")

    if [[ -z "$REPO_PATH" ]]; then
      $EWW_CMD update error_notification="Repository not found: $REPO_QUALIFIED"
      $EWW_CMD update error_notification_visible=true
      $EWW_CMD update worktree_delete_dialog_visible=false
      exit 1
    fi

    # Get worktree path
    WORKTREE_PATH=$(${pkgs.jq}/bin/jq -r --arg acc "$REPO_ACCOUNT" --arg name "$REPO_NAME" --arg branch "$BRANCH_NAME" \
      '.repositories[] | select(.account == $acc and .name == $name) | .worktrees[]? | select(.branch == $branch) | .path // empty' "$REPOS_FILE")

    if [[ -z "$WORKTREE_PATH" ]]; then
      $EWW_CMD update error_notification="Worktree not found: $BRANCH_NAME"
      $EWW_CMD update error_notification_visible=true
      $EWW_CMD update worktree_delete_dialog_visible=false
      exit 1
    fi

    # gtr-first removal through i3pm worktree command
    if ! i3pm worktree remove "$BRANCH_NAME" --repo "$REPO_QUALIFIED" --force 2>&1; then
      $EWW_CMD update error_notification="Failed to remove worktree: $BRANCH_NAME"
      $EWW_CMD update error_notification_visible=true
      $EWW_CMD update worktree_delete_dialog_visible=false
      exit 1
    fi

    # Close dialog and show success
    $EWW_CMD update worktree_delete_dialog_visible=false
    $EWW_CMD update worktree_delete_name=""
    $EWW_CMD update worktree_delete_branch=""
    $EWW_CMD update worktree_delete_is_dirty=false
    $EWW_CMD update success_notification="Worktree '$BRANCH_NAME' deleted successfully"
    $EWW_CMD update success_notification_visible=true
    (sleep 3 && $EWW_CMD update success_notification_visible=false success_notification="") &

    echo "Worktree deleted: $QUALIFIED_NAME"
  '';

  # Feature 102: Cancel worktree deletion
  worktreeDeleteCancelScript = pkgs.writeShellScriptBin "worktree-delete-cancel" ''
    #!${pkgs.bash}/bin/bash
    # Cancel worktree delete dialog
    # Usage: worktree-delete-cancel

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    $EWW_CMD update worktree_delete_dialog_visible=false
    $EWW_CMD update worktree_delete_name=""
    $EWW_CMD update worktree_delete_branch=""
    $EWW_CMD update worktree_delete_is_dirty=false
  '';

  # Feature 102: Validate branch name and check for duplicates
  worktreeValidateBranchScript = pkgs.writeShellScriptBin "worktree-validate-branch" ''
    #!${pkgs.bash}/bin/bash
    # Validate branch name for worktree creation
    # Usage: worktree-validate-branch <branch_name> <parent_project>
    # Returns: JSON with validation result

    BRANCH_NAME="$1"
    PARENT_PROJECT="$2"
    REPOS_FILE="$HOME/.config/i3/repos.json"

    # Validate branch name using git's own ref rules
    if ! ${pkgs.git}/bin/git check-ref-format --branch "$BRANCH_NAME" >/dev/null 2>&1; then
      echo "{\"valid\": false, \"error\": \"Invalid git branch name: $BRANCH_NAME\"}"
      exit 0
    fi

    # Check for existing branch with same name
    if [[ -f "$REPOS_FILE" ]]; then
      REPO_ACCOUNT=$(echo "$PARENT_PROJECT" | cut -d'/' -f1)
      REPO_NAME=$(echo "$PARENT_PROJECT" | cut -d'/' -f2)

      EXISTING=$(${pkgs.jq}/bin/jq -r --arg acc "$REPO_ACCOUNT" --arg name "$REPO_NAME" --arg branch "$BRANCH_NAME" \
        '.repositories[] | select(.account == $acc and .name == $name) | .worktrees[]? | select(.branch == $branch) | .branch' "$REPOS_FILE")

      if [[ -n "$EXISTING" ]]; then
        echo "{\"valid\": false, \"error\": \"Branch '$BRANCH_NAME' already exists as a worktree\"}"
        exit 0
      fi
    fi

    echo '{"valid": true, "error": ""}'
  '';

  # Feature 094 US5: Worktree edit form opener (T059)
  worktreeEditOpenScript = pkgs.writeShellScriptBin "worktree-edit-open" ''
    #!${pkgs.bash}/bin/bash
    # Open worktree rename form by loading worktree data into eww variables
    # Usage: worktree-edit-open <qualified_name> <branch_name> <worktree_path> <parent_project>

    QUALIFIED_NAME="$1"
    BRANCH_NAME="$2"
    WORKTREE_PATH="$3"
    PARENT_PROJECT="$4"

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Feature 114: Enable focus mode so form inputs are clickable
    $EWW_CMD update panel_focus_mode=true

    # Update all eww variables for worktree edit
    $EWW_CMD update editing_project_name="$QUALIFIED_NAME"
    $EWW_CMD update worktree_form_branch_name="$BRANCH_NAME"
    $EWW_CMD update worktree_form_path="$WORKTREE_PATH"
    $EWW_CMD update worktree_form_parent_project="$PARENT_PROJECT"
    $EWW_CMD update edit_form_error=""
  '';

  # Feature 094 US5: Worktree create script (T057-T058)
  worktreeCreateScript = pkgs.writeShellScriptBin "worktree-create" ''
    #!${pkgs.bash}/bin/bash
    # Create a new Git worktree and project config
    # Usage: worktree-create

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Feature 096 T022: Set loading state to prevent double-submit
    $EWW update save_in_progress=true

    # Read form values from Eww variables
    BRANCH_NAME=$($EWW get worktree_form_branch_name)
    BASE_BRANCH=$($EWW get worktree_form_base_branch 2>/dev/null || echo "main")
    WORKTREE_PATH=$($EWW get worktree_form_path 2>/dev/null || echo "")
    PARENT_PROJECT=$($EWW get worktree_form_parent_project)
    REMOTE_ENABLED=$($EWW get worktree_form_remote_enabled 2>/dev/null || echo "false")
    REMOTE_HOST=$($EWW get worktree_form_remote_host 2>/dev/null || echo "ryzen")
    REMOTE_USER=$($EWW get worktree_form_remote_user 2>/dev/null || echo "''${USER:-vpittamp}")
    REMOTE_DIR=$($EWW get worktree_form_remote_dir 2>/dev/null || echo "")
    REMOTE_PORT=$($EWW get worktree_form_remote_port 2>/dev/null || echo "22")

    # Validate required fields
    if [[ -z "$BRANCH_NAME" ]]; then
      $EWW update edit_form_error="Branch name is required"
      # Feature 096 T024: Show error notification
      $EWW update error_notification="Branch name is required"
      $EWW update error_notification_visible=true
      $EWW update save_in_progress=false
      exit 1
    fi
    if [[ -z "$PARENT_PROJECT" ]]; then
      $EWW update edit_form_error="Parent project is required"
      # Feature 096 T024: Show error notification
      $EWW update error_notification="Parent project is required"
      $EWW update error_notification_visible=true
      $EWW update save_in_progress=false
      exit 1
    fi

    if [[ "$REMOTE_ENABLED" == "true" ]]; then
      if [[ -z "$REMOTE_HOST" ]] || [[ -z "$REMOTE_USER" ]] || [[ -z "$REMOTE_DIR" ]]; then
        $EWW update edit_form_error="SSH host, user, and remote directory are required when remote profile is enabled"
        $EWW update error_notification="SSH remote profile is incomplete"
        $EWW update error_notification_visible=true
        $EWW update save_in_progress=false
        exit 1
      fi
      if [[ ! "$REMOTE_PORT" =~ ^[0-9]+$ ]] || [[ "$REMOTE_PORT" -lt 1 ]] || [[ "$REMOTE_PORT" -gt 65535 ]]; then
        $EWW update edit_form_error="SSH port must be a number between 1 and 65535"
        $EWW update error_notification="Invalid SSH port"
        $EWW update error_notification_visible=true
        $EWW update save_in_progress=false
        exit 1
      fi
    fi

    if [[ -z "$BASE_BRANCH" ]]; then
      BASE_BRANCH="main"
    fi

    # Feature 101: Get parent project directory from repos.json
    # PARENT_PROJECT is now a qualified name: account/repo (e.g., vpittamp/nixos-config)
    REPOS_FILE="$HOME/.config/i3/repos.json"
    if [[ ! -f "$REPOS_FILE" ]]; then
      $EWW update edit_form_error="repos.json not found. Run 'i3pm discover' first."
      $EWW update error_notification="repos.json not found. Run 'i3pm discover' first."
      $EWW update error_notification_visible=true
      $EWW update save_in_progress=false
      exit 1
    fi

    # Parse qualified name: account/repo
    REPO_ACCOUNT=$(echo "$PARENT_PROJECT" | cut -d'/' -f1)
    REPO_NAME=$(echo "$PARENT_PROJECT" | cut -d'/' -f2)

    # Find repo in repos.json
    PARENT_DIR=$(${pkgs.jq}/bin/jq -r --arg acc "$REPO_ACCOUNT" --arg name "$REPO_NAME" \
      '.repositories[] | select(.account == $acc and .name == $name) | .path // empty' "$REPOS_FILE")
    if [[ -z "$PARENT_DIR" ]]; then
      $EWW update edit_form_error="Repository not found: $PARENT_PROJECT"
      # Feature 096 T024: Show error notification
      $EWW update error_notification="Repository not found: $PARENT_PROJECT"
      $EWW update error_notification_visible=true
      $EWW update save_in_progress=false
      exit 1
    fi

    # Feature 102: Check for duplicate branch name (worktree already exists)
    EXISTING_BRANCH=$(${pkgs.jq}/bin/jq -r --arg acc "$REPO_ACCOUNT" --arg name "$REPO_NAME" --arg branch "$BRANCH_NAME" \
      '.repositories[] | select(.account == $acc and .name == $name) | .worktrees[]? | select(.branch == $branch) | .branch // empty' "$REPOS_FILE")
    if [[ -n "$EXISTING_BRANCH" ]]; then
      $EWW update edit_form_error="Branch '$BRANCH_NAME' already exists as a worktree"
      $EWW update error_notification="Worktree already exists: $BRANCH_NAME"
      $EWW update error_notification_visible=true
      $EWW update save_in_progress=false
      exit 1
    fi

    # Execute i3pm worktree create (gtr-backed)
    if ! i3pm worktree create "$BRANCH_NAME" --repo "$PARENT_PROJECT" --from "$BASE_BRANCH" 2>&1; then
      $EWW update edit_form_error="Worktree creation failed. Check console for details."
      $EWW update error_notification="Worktree creation failed"
      $EWW update error_notification_visible=true
      $EWW update save_in_progress=false
      exit 1
    fi

    # Feature 101: Generate qualified worktree name
    # Format: account/repo:branch (e.g., vpittamp/nixos-config:101-worktree-click-switch)
    WORKTREE_NAME="''${PARENT_PROJECT}:''${BRANCH_NAME}"

    REMOTE_WARNING=""
    if [[ "$REMOTE_ENABLED" == "true" ]]; then
      if ! i3pm worktree remote set "$WORKTREE_NAME" --host "$REMOTE_HOST" --user "$REMOTE_USER" --port "$REMOTE_PORT" --dir "$REMOTE_DIR" >/dev/null 2>&1; then
        REMOTE_WARNING="Worktree created, but failed to set SSH profile for $WORKTREE_NAME"
      fi
    fi

    # Success: clear form state and refresh
    # Feature 114: Disable focus mode to return to click-through
    $EWW update panel_focus_mode=false
    $EWW update worktree_creating=false
    $EWW update worktree_form_description=""
    $EWW update worktree_form_branch_name=""
    $EWW update worktree_form_base_branch="main"
    $EWW update worktree_form_path=""
    $EWW update worktree_form_parent_project=""
    $EWW update worktree_form_repo_path=""
    $EWW update worktree_form_remote_enabled=false
    $EWW update worktree_form_remote_host="ryzen"
    $EWW update worktree_form_remote_user=""
    $EWW update worktree_form_remote_dir=""
    $EWW update worktree_form_remote_port="22"
    $EWW update worktree_form_remote_base=""
    $EWW update edit_form_display_name=""
    $EWW update edit_form_icon=""
    $EWW update edit_form_error=""
    $EWW update save_in_progress=false

    refresh-projects-data >/dev/null 2>&1 || true

    if [[ -n "$REMOTE_WARNING" ]]; then
      $EWW update warning_notification="$REMOTE_WARNING"
      $EWW update warning_notification_visible=true
      (sleep 5 && $EWW update warning_notification_visible=false warning_notification="") &
    else
      if [[ "$REMOTE_ENABLED" == "true" ]]; then
        $EWW update success_notification="Worktree '$WORKTREE_NAME' created (SSH: $REMOTE_USER@$REMOTE_HOST:$REMOTE_PORT)"
      else
        $EWW update success_notification="Worktree '$WORKTREE_NAME' created • Use t/l/y for terminal, lazygit, yazi"
      fi
      $EWW update success_notification_visible=true
      (sleep 3 && $EWW update success_notification_visible=false success_notification="") &
    fi
  '';

  # Feature 094 US5: Worktree delete script (T060)
  worktreeDeleteScript = pkgs.writeShellScriptBin "worktree-delete" ''
    #!${pkgs.bash}/bin/bash
    # Delete a Git worktree and its project config
    # Usage: worktree-delete <project-name>

    PROJECT_NAME="$1"
    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    if [[ -z "$PROJECT_NAME" ]]; then
      echo "Usage: worktree-delete <project-name>" >&2
      exit 1
    fi

    # Check if user confirmed deletion
    CONFIRM=$($EWW get worktree_delete_confirm)
    if [[ "$CONFIRM" != "$PROJECT_NAME" ]]; then
      # First click - set confirmation state
      $EWW update worktree_delete_confirm="$PROJECT_NAME"
      echo "Click again to confirm deletion of: $PROJECT_NAME"
      exit 0
    fi

    # Feature 096 T022: Set loading state
    $EWW update save_in_progress=true

    # Feature 101: User confirmed - proceed with deletion using repos.json
    # PROJECT_NAME is now a qualified name: account/repo:branch
    REPOS_FILE="$HOME/.config/i3/repos.json"
    if [[ ! -f "$REPOS_FILE" ]]; then
      $EWW update edit_form_error="repos.json not found"
      $EWW update error_notification="repos.json not found. Run 'i3pm discover' first."
      $EWW update error_notification_visible=true
      $EWW update worktree_delete_confirm=""
      $EWW update save_in_progress=false
      exit 1
    fi

    # Parse qualified name: account/repo:branch
    REPO_PART=$(echo "$PROJECT_NAME" | cut -d':' -f1)
    BRANCH_NAME=$(echo "$PROJECT_NAME" | cut -d':' -f2)
    REPO_ACCOUNT=$(echo "$REPO_PART" | cut -d'/' -f1)
    REPO_NAME=$(echo "$REPO_PART" | cut -d'/' -f2)

    # Verify branch exists in discovery data
    EXISTING_BRANCH=$(${pkgs.jq}/bin/jq -r --arg acc "$REPO_ACCOUNT" --arg name "$REPO_NAME" --arg branch "$BRANCH_NAME" \
      '.repositories[] | select(.account == $acc and .name == $name) | .worktrees[]? | select(.branch == $branch) | .branch // empty' "$REPOS_FILE")

    if [[ -z "$EXISTING_BRANCH" ]]; then
      $EWW update edit_form_error="Worktree not found: $PROJECT_NAME"
      # Feature 096 T024: Show error notification
      $EWW update error_notification="Worktree not found: $PROJECT_NAME"
      $EWW update error_notification_visible=true
      $EWW update worktree_delete_confirm=""
      $EWW update save_in_progress=false
      exit 1
    fi

    # gtr-first delete workflow
    if ! i3pm worktree remove "$BRANCH_NAME" --repo "$REPO_PART" --force >/dev/null 2>&1; then
      $EWW update edit_form_error="Failed to remove worktree: $PROJECT_NAME"
      $EWW update error_notification="Failed to remove worktree: $PROJECT_NAME"
      $EWW update error_notification_visible=true
      $EWW update worktree_delete_confirm=""
      $EWW update save_in_progress=false
      exit 1
    fi

    # Success: clear state and refresh
    $EWW update worktree_delete_confirm=""
    $EWW update edit_form_error=""

    # Note: Project list will be refreshed by the deflisten stream automatically

    # Feature 096 T023: Show success notification (with optional warning)
    $EWW update success_notification="Worktree '$PROJECT_NAME' deleted successfully"
    $EWW update success_notification_visible=true
    (sleep 3 && $EWW update success_notification_visible=false success_notification="") &

    # Feature 096 T022: Clear loading state
    $EWW update save_in_progress=false

    echo "Worktree deleted successfully: $PROJECT_NAME"
  '';

  # Feature 099 T015: Toggle project expand/collapse script
  toggleProjectExpandedScript = pkgs.writeShellScriptBin "toggle-project-expanded" ''
    #!${pkgs.bash}/bin/bash
    # Toggle expand/collapse state for a repository project
    # Usage: toggle-project-expanded <project-name>

    PROJECT_NAME="$1"
    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"
    RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    PROJECTS_DATA_FILE="$RUNTIME_DIR/eww-monitoring-projects.json"

    if [[ -z "$PROJECT_NAME" ]]; then
      echo "Usage: toggle-project-expanded <project-name>" >&2
      exit 1
    fi

    # Get current expanded projects state
    CURRENT=$($EWW get expanded_projects)

    # Handle "all" case - when all expanded, clicking collapses just this one
    if [[ "$CURRENT" == "all" ]]; then
      # Get all project names and remove the clicked one
      if [[ -s "$PROJECTS_DATA_FILE" ]]; then
        PROJECTS_DATA=$(${pkgs.coreutils}/bin/cat "$PROJECTS_DATA_FILE")
      else
        PROJECTS_DATA='{"discovered_repositories":[],"repositories":[],"projects":[],"main_projects":[]}'
      fi
      ALL_NAMES=$(echo "$PROJECTS_DATA" | ${pkgs.jq}/bin/jq -r '
        [
          .discovered_repositories[]?.qualified_name // empty,
          .repositories[]?.qualified_name // empty,
          .projects[]?.name // empty,
          .main_projects[]?.name // empty
        ] | unique
      ')
      NEW=$(echo "$ALL_NAMES" | ${pkgs.jq}/bin/jq -c "del(.[] | select(. == \"$PROJECT_NAME\"))")
      $EWW update "expanded_projects=$NEW" "projects_all_expanded=false"
    elif echo "$CURRENT" | ${pkgs.jq}/bin/jq -e "index(\"$PROJECT_NAME\")" > /dev/null 2>&1; then
      # Remove from array (collapse)
      NEW=$(echo "$CURRENT" | ${pkgs.jq}/bin/jq -c "del(.[] | select(. == \"$PROJECT_NAME\"))")
      $EWW update "expanded_projects=$NEW"
    else
      # Add to array (expand)
      NEW=$(echo "$CURRENT" | ${pkgs.jq}/bin/jq -c ". + [\"$PROJECT_NAME\"]")
      $EWW update "expanded_projects=$NEW"
    fi
  '';

  # Feature 099 UX3: Expand/collapse all repositories script
  toggleExpandAllScript = pkgs.writeShellScriptBin "toggle-expand-all-projects" ''
    #!${pkgs.bash}/bin/bash
    # Toggle expand/collapse all repositories
    # Usage: toggle-expand-all-projects

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Get current all_expanded state
    CURRENT_STATE=$($EWW get projects_all_expanded)

    if [[ "$CURRENT_STATE" == "true" ]]; then
      # Currently expanded, collapse all
      $EWW update projects_all_expanded=false
      $EWW update 'expanded_projects=[]'
    else
      # Currently collapsed, expand all - use "all" marker
      $EWW update projects_all_expanded=true
      $EWW update 'expanded_projects=all'
    fi
  '';

  # Feature 094 US5: Worktree edit save script (T059)
  worktreeEditSaveScript = pkgs.writeShellScriptBin "worktree-edit-save" ''
    #!${pkgs.bash}/bin/bash
    # Rename worktree/branch using i3pm gtr-backed command
    # Usage: worktree-edit-save <qualified-name>

    PROJECT_NAME="$1"
    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    if [[ -z "$PROJECT_NAME" ]]; then
      echo "Usage: worktree-edit-save <project-name>" >&2
      exit 1
    fi

    # Feature 096 T022: Set loading state to prevent double-submit
    $EWW update save_in_progress=true

    OLD_BRANCH=$(echo "$PROJECT_NAME" | cut -d':' -f2)
    NEW_BRANCH=$($EWW get worktree_form_branch_name)

    if [[ -z "$NEW_BRANCH" ]]; then
      $EWW update edit_form_error="New branch name is required"
      $EWW update error_notification="New branch name is required"
      $EWW update error_notification_visible=true
      $EWW update save_in_progress=false
      exit 1
    fi

    if [[ "$NEW_BRANCH" == "$OLD_BRANCH" ]]; then
      $EWW update panel_focus_mode=false
      $EWW update editing_project_name=""
      $EWW update edit_form_error=""
      $EWW update save_in_progress=false
      $EWW update success_notification="No changes to save"
      $EWW update success_notification_visible=true
      (sleep 2 && $EWW update success_notification_visible=false success_notification="") &
      exit 0
    fi

    RENAME_LOG=$(mktemp)
    if ! i3pm worktree rename "$PROJECT_NAME" "$NEW_BRANCH" >"$RENAME_LOG" 2>&1; then
      ERROR=$(cat "$RENAME_LOG")
      rm -f "$RENAME_LOG"
      $EWW update edit_form_error="Failed to rename worktree"
      $EWW update error_notification="Failed to rename worktree: $ERROR"
      $EWW update error_notification_visible=true
      $EWW update save_in_progress=false
      exit 1
    fi
    rm -f "$RENAME_LOG"

    NEW_QUALIFIED="$(echo "$PROJECT_NAME" | cut -d':' -f1):$NEW_BRANCH"

    # Success: clear editing state and refresh
    $EWW update panel_focus_mode=false
    $EWW update editing_project_name=""
    $EWW update edit_form_error=""
    $EWW update save_in_progress=false

    refresh-projects-data >/dev/null 2>&1 || true

    $EWW update success_notification="Renamed worktree to '$NEW_QUALIFIED'"
    $EWW update success_notification_visible=true
    (sleep 3 && $EWW update success_notification_visible=false success_notification="") &

    echo "Worktree renamed: $PROJECT_NAME -> $NEW_QUALIFIED"
  '';

  # Feature 094 US3: Project create form opener (T066)
  projectCreateOpenScript = pkgs.writeShellScriptBin "project-create-open" ''
    #!${pkgs.bash}/bin/bash
    # Open project create form by setting state and clearing form fields
    # Usage: project-create-open

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Feature 114: Enable focus mode so form inputs are clickable
    $EWW_CMD update panel_focus_mode=true

    # Clear all form fields for new project
    $EWW_CMD update create_form_name=""
    $EWW_CMD update create_form_display_name=""
    $EWW_CMD update create_form_icon="📦"
    $EWW_CMD update create_form_working_dir=""
    $EWW_CMD update create_form_scope="scoped"
    $EWW_CMD update create_form_remote_enabled=false
    $EWW_CMD update create_form_remote_host=""
    $EWW_CMD update create_form_remote_user=""
    $EWW_CMD update create_form_remote_dir=""
    $EWW_CMD update create_form_remote_port="22"
    $EWW_CMD update create_form_error=""

    # Show the create form
    $EWW_CMD update project_creating=true
  '';

  # Feature 094 US3: Project create form save handler (T069)
  projectCreateSaveScript = pkgs.writeShellScriptBin "project-create-save" ''
    #!${pkgs.bash}/bin/bash
    # Save project create form by reading Eww variables and calling CRUD handler
    # Usage: project-create-save

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Feature 096 T022: Set loading state to prevent double-submit
    $EWW update save_in_progress=true

    # Read form values from Eww variables
    NAME=$($EWW get create_form_name)
    DISPLAY_NAME=$($EWW get create_form_display_name)
    ICON=$($EWW get create_form_icon)
    WORKING_DIR=$($EWW get create_form_working_dir)
    SCOPE=$($EWW get create_form_scope)
    REMOTE_ENABLED=$($EWW get create_form_remote_enabled)
    REMOTE_HOST=$($EWW get create_form_remote_host)
    REMOTE_USER=$($EWW get create_form_remote_user)
    REMOTE_DIR=$($EWW get create_form_remote_dir)
    REMOTE_PORT=$($EWW get create_form_remote_port)

    # Client-side validation
    if [[ -z "$NAME" ]]; then
      $EWW update create_form_error="Project name is required"
      # Feature 096 T024: Show error notification
      $EWW update error_notification="Project name is required"
      $EWW update error_notification_visible=true
      $EWW update save_in_progress=false
      exit 1
    fi

    if [[ -z "$WORKING_DIR" ]]; then
      $EWW update create_form_error="Working directory is required"
      # Feature 096 T024: Show error notification
      $EWW update error_notification="Working directory is required"
      $EWW update error_notification_visible=true
      $EWW update save_in_progress=false
      exit 1
    fi

    # If display name is empty, use name
    if [[ -z "$DISPLAY_NAME" ]]; then
      DISPLAY_NAME="$NAME"
    fi

    # If icon is empty, use default
    if [[ -z "$ICON" ]]; then
      ICON="📦"
    fi

    # Build JSON config object
    if [[ "$REMOTE_ENABLED" == "true" ]]; then
      CONFIG=$(${pkgs.jq}/bin/jq -n \
        --arg name "$NAME" \
        --arg display_name "$DISPLAY_NAME" \
        --arg icon "$ICON" \
        --arg working_dir "$WORKING_DIR" \
        --arg scope "$SCOPE" \
        --argjson remote_enabled true \
        --arg remote_host "$REMOTE_HOST" \
        --arg remote_user "$REMOTE_USER" \
        --arg remote_dir "$REMOTE_DIR" \
        --argjson remote_port "$REMOTE_PORT" \
        '{
          name: $name,
          display_name: $display_name,
          icon: $icon,
          working_dir: $working_dir,
          scope: $scope,
          remote: {
            enabled: $remote_enabled,
            host: $remote_host,
            user: $remote_user,
            remote_dir: $remote_dir,
            port: $remote_port
          }
        }')
    else
      CONFIG=$(${pkgs.jq}/bin/jq -n \
        --arg name "$NAME" \
        --arg display_name "$DISPLAY_NAME" \
        --arg icon "$ICON" \
        --arg working_dir "$WORKING_DIR" \
        --arg scope "$SCOPE" \
        '{
          name: $name,
          display_name: $display_name,
          icon: $icon,
          working_dir: $working_dir,
          scope: $scope
        }')
    fi

    # Call Python CRUD handler
    export PYTHONPATH="${../../../tools}:${../../../tools/monitoring-panel}"
    RESULT=$(${pythonForBackend}/bin/python3 <<EOF
import asyncio
import json
import sys
sys.path.insert(0, "${../../../tools}")
sys.path.insert(0, "${../../../tools/monitoring-panel}")
from project_crud_handler import ProjectCRUDHandler

handler = ProjectCRUDHandler()
request = {"action": "create_project", "config": $CONFIG}
result = asyncio.run(handler.handle_request(request))
print(json.dumps(result))
EOF
)

    # Check result
    SUCCESS=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.success')
    if [[ "$SUCCESS" == "true" ]]; then
      # Success: clear form state and refresh
      # Feature 114: Disable focus mode to return to click-through
      $EWW update panel_focus_mode=false
      $EWW update project_creating=false
      $EWW update create_form_name=""
      $EWW update create_form_display_name=""
      $EWW update create_form_icon="📦"
      $EWW update create_form_working_dir=""
      $EWW update create_form_scope="scoped"
      $EWW update create_form_remote_enabled=false
      $EWW update create_form_remote_host=""
      $EWW update create_form_remote_user=""
      $EWW update create_form_remote_dir=""
      $EWW update create_form_remote_port="22"
      $EWW update create_form_error=""

      # Note: Project list will be refreshed by the deflisten stream automatically
      # Skipping manual refresh to avoid issues with large JSON payloads in eww update

      # Feature 096 T023: Show success notification
      $EWW update success_notification="Project '$NAME' created successfully"
      $EWW update success_notification_visible=true
      # Auto-dismiss after 3 seconds (T020)
      (sleep 3 && $EWW update success_notification_visible=false success_notification="") &

      # Feature 096 T022: Clear loading state
      $EWW update save_in_progress=false

      echo "Project created successfully: $NAME"
    else
      # Show error message
      ERROR_MSG=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.error_message')
      VALIDATION_ERRORS=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.validation_errors | length')

      if [[ "$VALIDATION_ERRORS" -gt 0 ]]; then
        FIRST_ERROR=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.validation_errors[0]')
        $EWW update create_form_error="$FIRST_ERROR"
        # Feature 096 T024: Show error notification
        $EWW update error_notification="Validation error: $FIRST_ERROR"
        $EWW update error_notification_visible=true
      elif [[ -n "$ERROR_MSG" ]] && [[ "$ERROR_MSG" != "null" ]]; then
        $EWW update create_form_error="$ERROR_MSG"
        # Feature 096 T024: Show error notification
        $EWW update error_notification="$ERROR_MSG"
        $EWW update error_notification_visible=true
      else
        $EWW update create_form_error="Failed to create project"
        # Feature 096 T024: Show error notification
        $EWW update error_notification="Failed to create project"
        $EWW update error_notification_visible=true
      fi

      # Feature 096 T022: Clear loading state on error
      $EWW update save_in_progress=false

      exit 1
    fi
  '';

  # Feature 094 US3: Project create form cancel handler (T066)
  projectCreateCancelScript = pkgs.writeShellScriptBin "project-create-cancel" ''
    #!${pkgs.bash}/bin/bash
    # Cancel project create form
    # Usage: project-create-cancel

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Feature 114: Disable focus mode to return to click-through
    $EWW update panel_focus_mode=false

    # Hide form and clear all fields
    $EWW update project_creating=false
    $EWW update create_form_name=""
    $EWW update create_form_display_name=""
    $EWW update create_form_icon="📦"
    $EWW update create_form_working_dir=""
    $EWW update create_form_scope="scoped"
    $EWW update create_form_remote_enabled=false
    $EWW update create_form_remote_host=""
    $EWW update create_form_remote_user=""
    $EWW update create_form_remote_dir=""
    $EWW update create_form_remote_port="22"
    $EWW update create_form_error=""
  '';

  projectDeleteOpenScript = pkgs.writeShellScriptBin "project-delete-open" ''
    #!${pkgs.bash}/bin/bash
    # Open project delete confirmation dialog
    # Usage: project-delete-open <project_name> <display_name>

    set -euo pipefail

    PROJECT_NAME="''${1:-}"
    DISPLAY_NAME="''${2:-}"

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    if [[ -z "$PROJECT_NAME" ]]; then
      echo "Error: Project name required" >&2
      exit 1
    fi

    # Check if project has worktrees by looking for worktrees with this parent
    PROJECTS_DIR="$HOME/.config/i3/projects"
    HAS_WORKTREES="false"
    for f in "$PROJECTS_DIR"/*.json; do
      if [[ -f "$f" ]]; then
        PARENT=$(${pkgs.jq}/bin/jq -r '.parent_project // empty' "$f" 2>/dev/null || echo "")
        if [[ "$PARENT" == "$PROJECT_NAME" ]]; then
          HAS_WORKTREES="true"
          break
        fi
      fi
    done

    # Clear previous state
    $EWW update delete_error=""
    $EWW update delete_success_message=""
    $EWW update delete_force=false

    # Set dialog state
    $EWW update delete_project_name="$PROJECT_NAME"
    $EWW update delete_project_display_name="''${DISPLAY_NAME:-$PROJECT_NAME}"
    $EWW update delete_project_has_worktrees="$HAS_WORKTREES"
    $EWW update project_deleting=true
  '';

  # Feature 094 US4: Project delete confirm handler (T088)
  projectDeleteConfirmScript = pkgs.writeShellScriptBin "project-delete-confirm" ''
    #!${pkgs.bash}/bin/bash
    # Execute project deletion via CRUD handler
    # Usage: project-delete-confirm

    set -euo pipefail

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Read deletion parameters
    PROJECT_NAME=$($EWW get delete_project_name)
    FORCE=$($EWW get delete_force)

    if [[ -z "$PROJECT_NAME" ]]; then
      $EWW update delete_error="No project selected for deletion"
      exit 1
    fi

    # Build request JSON
    if [[ "$FORCE" == "true" ]]; then
      REQUEST=$(${pkgs.jq}/bin/jq -n \
        --arg name "$PROJECT_NAME" \
        '{"action": "delete_project", "project_name": $name, "force": true}')
    else
      REQUEST=$(${pkgs.jq}/bin/jq -n \
        --arg name "$PROJECT_NAME" \
        '{"action": "delete_project", "project_name": $name}')
    fi

    echo "Deleting project: $PROJECT_NAME (force=$FORCE)" >&2

    # Call the CRUD handler
    export PYTHONPATH="${../../../tools}:${../../../tools/monitoring-panel}"
    RESULT=$(echo "$REQUEST" | ${pythonForBackend}/bin/python3 -c "
import sys
sys.path.insert(0, '${../../../tools}')
sys.path.insert(0, '${../../../tools/monitoring-panel}')
from project_crud_handler import ProjectCRUDHandler
import asyncio
import json

handler = ProjectCRUDHandler()
request = json.loads(sys.stdin.read())
result = asyncio.run(handler.handle_request(request))
print(json.dumps(result))
")

    # Check result
    SUCCESS=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.success')

    if [[ "$SUCCESS" == "true" ]]; then
      # Success - close dialog
      $EWW update project_deleting=false
      $EWW update delete_project_name=""
      $EWW update delete_project_display_name=""
      $EWW update delete_project_has_worktrees=false
      $EWW update delete_force=false
      $EWW update delete_error=""

      # Note: Project list will be refreshed by the deflisten stream automatically

      # Feature 096 T023: Show success notification via eww (consistent with create/edit)
      $EWW update success_notification="Project '$PROJECT_NAME' deleted successfully"
      $EWW update success_notification_visible=true
      # Auto-dismiss after 3 seconds (T020)
      (sleep 3 && $EWW update success_notification_visible=false success_notification="") &

      echo "Project deleted successfully: $PROJECT_NAME"
    else
      # Show error in dialog
      ERROR_MSG=$(echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.error_message')
      $EWW update delete_error="$ERROR_MSG"

      # Feature 096 T024: Show error notification via eww
      $EWW update error_notification="Delete failed: $ERROR_MSG"
      $EWW update error_notification_visible=true

      echo "Error deleting project: $ERROR_MSG" >&2
      exit 1
    fi
  '';

  # Feature 094 US4: Project delete cancel handler (T089)
  projectDeleteCancelScript = pkgs.writeShellScriptBin "project-delete-cancel" ''
    #!${pkgs.bash}/bin/bash
    # Cancel project delete confirmation dialog
    # Usage: project-delete-cancel

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Hide dialog and clear state
    $EWW update project_deleting=false
    $EWW update delete_project_name=""
    $EWW update delete_project_display_name=""
    $EWW update delete_project_has_worktrees=false
    $EWW update delete_force=false
    $EWW update delete_error=""
  '';

  projectsNavScript = pkgs.writeShellScriptBin "projects-nav" ''
    #!${pkgs.bash}/bin/bash
    # Feature 099 UX2: Handle keyboard navigation within Projects tab
    # Usage: projects-nav <action>
    # Actions: down, up, select, expand, edit, delete, copy, new

    ACTION="$1"
    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"
    RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    PROJECTS_DATA_FILE="$RUNTIME_DIR/eww-monitoring-projects.json"

    # Get current state
    current_index=$($EWW_CMD get project_selected_index 2>/dev/null || echo "-1")
    filter_text=$($EWW_CMD get project_filter 2>/dev/null || echo "")

    # Get filtered project list
    if [[ -s "$PROJECTS_DATA_FILE" ]]; then
      projects_data=$(${pkgs.coreutils}/bin/cat "$PROJECTS_DATA_FILE")
    else
      projects_data='{"discovered_repositories":[],"repositories":[],"projects":[],"main_projects":[],"worktrees":[]}'
    fi

    # Build combined list from discovered repositories + legacy structures.
    # Each entry: { name, type: "project"|"worktree", parent?, index }
    all_items=$(echo "$projects_data" | ${pkgs.jq}/bin/jq -c --arg filter "$filter_text" '
      def txt(v): (v // "" | tostring);
      def contains_filter(v):
        if $filter == "" then true
        else (txt(v) | ascii_downcase | contains($filter | ascii_downcase))
        end;

      (
        [
          (.discovered_repositories // .repositories // [])[] as $repo
          | select(
              contains_filter($repo.qualified_name)
              or contains_filter($repo.name)
              or contains_filter($repo.display_name)
              or contains_filter($repo.account)
            )
          | {
              name: ($repo.qualified_name // $repo.name // ""),
              type: "project",
              display_name: ($repo.display_name // $repo.name // $repo.qualified_name // ""),
              directory: ($repo.directory // $repo.path // "")
            }
        ]
        +
        [
          (.discovered_repositories // .repositories // [])[] as $repo
          | ($repo.worktrees // [])[] as $wt
          | select(
              contains_filter($wt.qualified_name)
              or contains_filter($wt.branch)
              or contains_filter($wt.display_name)
              or contains_filter($wt.branch_number)
            )
          | {
              name: (
                $wt.qualified_name
                // (($repo.qualified_name // $repo.name // "") + ":" + ($wt.branch // $wt.name // ""))
              ),
              type: "worktree",
              parent: ($repo.qualified_name // $repo.name // ""),
              display_name: ($wt.display_name // $wt.branch // $wt.name // ""),
              directory: (
                if ($wt.remote_enabled // false)
                then ($wt.remote.remote_dir // $wt.remote_dir // $wt.path // $wt.directory // "")
                else ($wt.path // $wt.directory // "")
                end
              )
            }
        ]
        +
        [
          (.main_projects // [])[]
          | select(
              contains_filter(.name)
              or contains_filter(.display_name)
              or contains_filter(.branch_name)
            )
          | {
              name: .name,
              type: "project",
              display_name: (.display_name // .name // ""),
              directory: (.directory // .worktree_path // "")
            }
        ]
        +
        [
          (.worktrees // [])[]
          | select(
              contains_filter(.name)
              or contains_filter(.display_name)
              or contains_filter(.branch_name)
            )
          | {
              name: .name,
              type: "worktree",
              parent: (.parent_project // ""),
              display_name: (.display_name // .name // ""),
              directory: (.worktree_path // .directory // "")
            }
        ]
      )
      | map(select(.name != "" and .name != null))
      | unique_by(.name)
    ')

    max_items=$(echo "$all_items" | ${pkgs.jq}/bin/jq 'length')

    # If no items, skip navigation
    if [ "$max_items" -eq 0 ]; then
      exit 0
    fi

    # Helper function to update selection by index
    update_selection() {
      local idx=$1
      local name=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson i "$idx" '.[$i].name // ""')
      $EWW_CMD update project_selected_index=$idx
      $EWW_CMD update "project_selected_name=$name"
    }

    case "$ACTION" in
      down|j)
        new_index=$((current_index + 1))
        if [ "$new_index" -ge "$max_items" ]; then
          new_index=$((max_items - 1))
        fi
        update_selection $new_index
        ;;
      up|k)
        new_index=$((current_index - 1))
        if [ "$new_index" -lt 0 ]; then
          new_index=0
        fi
        update_selection $new_index
        ;;
      first|g)
        update_selection 0
        ;;
      last|G)
        update_selection $((max_items - 1))
        ;;
      select|enter)
        # Switch to selected project
        if [ "$current_index" -ge 0 ] && [ "$current_index" -lt "$max_items" ]; then
          project_name=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].name')
          if [ -n "$project_name" ] && [ "$project_name" != "null" ]; then
            i3pm worktree switch "$project_name"
            # Feature 125: exit-monitor-mode removed (focus mode replaced by dock mode)
          fi
        fi
        ;;
      expand|space)
        # Toggle expand/collapse for selected project (if it's a main project)
        if [ "$current_index" -ge 0 ] && [ "$current_index" -lt "$max_items" ]; then
          item_type=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].type')
          project_name=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].name')
          if [ "$item_type" = "project" ] && [ -n "$project_name" ]; then
            toggle-project-expanded "$project_name"
          fi
        fi
        ;;
      edit|e)
        # Open edit form for selected project
        if [ "$current_index" -ge 0 ] && [ "$current_index" -lt "$max_items" ]; then
          project_name=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].name')
          item_type=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].type')
          if [ -n "$project_name" ] && [ "$project_name" != "null" ]; then
            if [ "$item_type" = "worktree" ]; then
              # Get worktree data for edit form
              worktree_data=$(echo "$projects_data" | ${pkgs.jq}/bin/jq -r --arg name "$project_name" '
                (
                  (.discovered_repositories // .repositories // [])[] as $repo
                  | ($repo.worktrees // [])[]
                  | select(
                      (.qualified_name // (($repo.qualified_name // "") + ":" + (.branch // ""))) == $name
                    )
                  | "\(.branch // .branch_name // "")\t\(.path // .directory // "")\t\($repo.qualified_name // .parent_repo // "")"
                ),
                (
                  (.worktrees // [])[] | select(.name == $name) |
                  "\(.branch_name // "")\t\(.worktree_path // .directory // "")\t\(.parent_project // "")"
                )
                | select(length > 0)
              ')
              IFS=$'\t' read -r branch_name worktree_path parent_project <<< "$worktree_data"
              worktree-edit-open "$project_name" "$branch_name" "$worktree_path" "$parent_project"
            else
              # Get project data for edit form
              project_data=$(echo "$projects_data" | ${pkgs.jq}/bin/jq -r --arg name "$project_name" '
                (
                  (.main_projects // [])[] | select(.name == $name) |
                  "\(.display_name // .name)\t\(.icon)\t\(.directory)\t\(.scope // "scoped")\t\(.remote.enabled // false)\t\(.remote.host // "")\t\(.remote.user // "")\t\(.remote.remote_dir // "")\t\(.remote.port // 22)"
                ),
                (
                  (.discovered_repositories // .repositories // [])[]
                  | select((.qualified_name // .name // "") == $name)
                  | "\(.display_name // .name // .qualified_name)\t\(.icon // "📂")\t\(.directory // .path // "")\t\("scoped")\t\(false)\t\("")\t\("")\t\("")\t\(22)"
                )
                | select(length > 0)
              ')
              IFS=$'\t' read -r display_name icon directory scope remote_enabled remote_host remote_user remote_dir remote_port <<< "$project_data"
              project-edit-open "$project_name" "$display_name" "$icon" "$directory" "$scope" "$remote_enabled" "$remote_host" "$remote_user" "$remote_dir" "$remote_port"
            fi
          fi
        fi
        ;;
      delete|d)
        # Open delete confirmation for selected project
        if [ "$current_index" -ge 0 ] && [ "$current_index" -lt "$max_items" ]; then
          project_name=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].name')
          display_name=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].display_name // .[$idx].name')
          item_type=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].type')
          if [ -n "$project_name" ] && [ "$project_name" != "null" ]; then
            if [ "$item_type" = "worktree" ]; then
              worktree-delete "$project_name"
            else
              project-delete-open "$project_name" "$display_name"
            fi
          fi
        fi
        ;;
      copy|y)
        # Copy directory path of selected project
        if [ "$current_index" -ge 0 ] && [ "$current_index" -lt "$max_items" ]; then
          directory=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].directory')
          if [ -n "$directory" ] && [ "$directory" != "null" ]; then
            echo -n "$directory" | ${pkgs.wl-clipboard}/bin/wl-copy
            $EWW_CMD update success_notification="Copied: $directory" success_notification_visible=true
            (sleep 2 && $EWW_CMD update success_notification_visible=false) &
          fi
        fi
        ;;
      new|n)
        # Open new project form
        project-create-open
        ;;
      git|Shift+l)
        # Feature 109 T028: Launch lazygit for selected worktree with context-aware view
        if [ "$current_index" -ge 0 ] && [ "$current_index" -lt "$max_items" ]; then
          directory=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].directory')
          project_name=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].name')
          if [ -n "$project_name" ] && [ "$project_name" != "null" ]; then
            # Keep active-worktree context aligned with selected item so SSH-aware
            # launchers can detect remote profiles reliably.
            i3pm worktree switch "$project_name" >/dev/null 2>&1 || true
          fi

          # Select view: dirty -> status, behind -> branch, else status.
          # Falls back to status if local metadata is unavailable.
          view="status"
          if [ -n "$directory" ] && [ "$directory" != "null" ] && [ -d "$directory" ]; then
            git_dirty=$(cd "$directory" && ${pkgs.git}/bin/git status --porcelain 2>/dev/null | head -1)
            git_behind=$(cd "$directory" && ${pkgs.git}/bin/git rev-list --count HEAD..@{u} 2>/dev/null || echo "0")
            if [ -z "$git_dirty" ] && [ "$git_behind" -gt 0 ]; then
              view="branch"
            fi
          fi

          if [ -n "$directory" ] && [ "$directory" != "null" ] && [ -d "$directory" ]; then
            worktree-lazygit "$directory" "$view" &
          elif [ -x "$HOME/.local/bin/app-launcher-wrapper.sh" ]; then
            "$HOME/.local/bin/app-launcher-wrapper.sh" lazygit &
          fi
          # Feature 125: exit-monitor-mode removed (focus mode replaced by dock mode)
        fi
        ;;
      filter|/)
        # Focus filter input (handled by Sway keybinding - this is a placeholder)
        # The actual focus requires direct eww interaction
        ;;
      clear-filter|escape)
        # Clear filter and reset selection
        $EWW_CMD update "project_filter="
        $EWW_CMD update project_selected_index=-1
        $EWW_CMD update "project_selected_name="
        ;;
      create-worktree|c)
        # Feature 109 T035: Open worktree create form for selected project
        if [ "$current_index" -ge 0 ] && [ "$current_index" -lt "$max_items" ]; then
          item_type=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].type')
          project_name=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].name')

          # If selected item is a worktree, use its parent project; otherwise use the project itself
          if [ "$item_type" = "worktree" ]; then
            parent_project=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].parent // ""')
            if [ -n "$parent_project" ] && [ "$parent_project" != "null" ]; then
              worktree-create-open "$parent_project"
            fi
          elif [ "$item_type" = "project" ]; then
            worktree-create-open "$project_name"
          fi
        fi
        ;;
      terminal|t)
        # Feature 109 T060: Open scratchpad terminal in selected worktree
        if [ "$current_index" -ge 0 ] && [ "$current_index" -lt "$max_items" ]; then
          project_name=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].name')
          if [ -n "$project_name" ] && [ "$project_name" != "null" ]; then
            i3pm scratchpad toggle "$project_name" &
            # Feature 125: exit-monitor-mode removed (focus mode replaced by dock mode)
          fi
        fi
        ;;
      editor|Shift+e)
        # Feature 109 T061: Open VS Code in selected worktree
        if [ "$current_index" -ge 0 ] && [ "$current_index" -lt "$max_items" ]; then
          directory=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].directory')
          if [ -n "$directory" ] && [ "$directory" != "null" ] && [ -d "$directory" ]; then
            code --folder-uri "file://$directory" &
            # Feature 125: exit-monitor-mode removed (focus mode replaced by dock mode)
          fi
        fi
        ;;
      files|Shift+f)
        # Feature 109 T055: Open file manager (yazi) in selected worktree
        if [ "$current_index" -ge 0 ] && [ "$current_index" -lt "$max_items" ]; then
          project_name=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].name')
          directory=$(echo "$all_items" | ${pkgs.jq}/bin/jq -r --argjson idx "$current_index" '.[$idx].directory')

          if [ -n "$project_name" ] && [ "$project_name" != "null" ]; then
            # Ensure launcher wrapper sees the selected worktree context (SSH/local).
            i3pm worktree switch "$project_name" >/dev/null 2>&1 || true
          fi

          if [ -x "$HOME/.local/bin/app-launcher-wrapper.sh" ]; then
            "$HOME/.local/bin/app-launcher-wrapper.sh" yazi &
          elif [ -n "$directory" ] && [ "$directory" != "null" ] && [ -d "$directory" ]; then
            ${pkgs.ghostty}/bin/ghostty -e ${pkgs.yazi}/bin/yazi "$directory" &
          fi
          # Feature 125: exit-monitor-mode removed (focus mode replaced by dock mode)
        fi
        ;;
      refresh|r)
        # Feature 109 T059: Refresh project list
        i3pm discover --quiet &
        $EWW_CMD update success_notification="Refreshing projects..." success_notification_visible=true
        (sleep 2 && $EWW_CMD update success_notification_visible=false) &
        ;;
    esac
  '';

  copyProjectJsonScript = pkgs.writeShellScript "copy-project-json" ''
    #!/usr/bin/env bash
    set -euo pipefail

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"
    PROJECT_NAME="''${1:-}"

    if [[ -z "$PROJECT_NAME" ]]; then
      echo "Usage: copy-project-json <qualified-name>" >&2
      echo "  qualified-name: account/repo:branch (e.g., vpittamp/nixos-config:main)" >&2
      exit 1
    fi

    # Feature 101: Extract worktree data from repos.json
    REPOS_FILE="$HOME/.config/i3/repos.json"
    if [[ ! -f "$REPOS_FILE" ]]; then
      echo "repos.json not found" >&2
      exit 1
    fi

    # Parse qualified name: account/repo:branch
    REPO_PART=$(echo "$PROJECT_NAME" | cut -d':' -f1)
    BRANCH_NAME=$(echo "$PROJECT_NAME" | cut -d':' -f2)
    REPO_ACCOUNT=$(echo "$REPO_PART" | cut -d'/' -f1)
    REPO_NAME=$(echo "$REPO_PART" | cut -d'/' -f2)

    # Extract worktree data and copy to clipboard
    ${pkgs.jq}/bin/jq --arg acc "$REPO_ACCOUNT" --arg name "$REPO_NAME" --arg branch "$BRANCH_NAME" \
      '.repositories[] | select(.account == $acc and .name == $name) | {
        repository: {account: .account, name: .name, path: .path, default_branch: .default_branch},
        worktree: (.worktrees[] | select(.branch == $branch))
      }' "$REPOS_FILE" | ${pkgs.wl-clipboard}/bin/wl-copy

    # Toggle copied state for visual feedback
    $EWW_CMD update copied_project_name="$PROJECT_NAME"
    (${pkgs.coreutils}/bin/sleep 2 && $EWW_CMD update copied_project_name="") &
  '';

  # Feature 101: Copy trace data to clipboard for LLM analysis

in
{
  inherit projectCrudScript projectEditOpenScript projectEditSaveScript
          projectConflictResolveScript formValidationStreamScript
          worktreeCreateOpenScript worktreeAutoPopulateScript worktreeUpdatePathScript
          worktreeDeleteOpenScript worktreeDeleteConfirmScript
          worktreeDeleteCancelScript worktreeValidateBranchScript
          worktreeEditOpenScript worktreeCreateScript worktreeDeleteScript
          toggleProjectExpandedScript toggleExpandAllScript worktreeEditSaveScript
          projectCreateOpenScript projectCreateSaveScript projectCreateCancelScript
          projectDeleteOpenScript projectDeleteConfirmScript projectDeleteCancelScript
          projectsNavScript copyProjectJsonScript;
}
