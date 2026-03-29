{ config, pkgs, lib, ... }:

let
  holmesVersion = "0.23.0";
  holmesInstallStamp = "${holmesVersion}+nixos3";
  anthropicApiKeyRef = "op://CLI/ANTHROPIC_API_KEY/credential";
  defaultModel = "anthropic/claude-sonnet-4-20250514";
  holmesStateDir = "${config.home.homeDirectory}/.local/share/holmesgpt";
  holmesToolDir = "${holmesStateDir}/tool";
  holmesBinDir = "${holmesToolDir}/venv/bin";
  realHolmes = "${holmesBinDir}/holmes";
  anthropicApiKeyCache = "${holmesStateDir}/anthropic_api_key";
  runtimeLibraryPath = lib.makeLibraryPath [
    pkgs.stdenv.cc.cc.lib
  ];

  holmesWrapper = pkgs.writeShellScriptBin "holmes" ''
    set -euo pipefail

    STATE_DIR="${holmesStateDir}"
    TOOL_DIR="${holmesToolDir}"
    BIN_DIR="${holmesBinDir}"
    REAL_HOLMES="${realHolmes}"
    VERSION_FILE="$STATE_DIR/version"
    DESIRED_VERSION="${holmesVersion}"
    INSTALL_STAMP="${holmesInstallStamp}"

    install_holmes() {
      local install_log

      ${pkgs.coreutils}/bin/mkdir -p "$STATE_DIR"
      ${pkgs.coreutils}/bin/rm -rf "$TOOL_DIR"
      install_log="$(${pkgs.coreutils}/bin/mktemp)"
      trap '${pkgs.coreutils}/bin/rm -f "$install_log"' RETURN

      if ! (
        UV_PYTHON="${pkgs.python3}/bin/python3" \
        UV_PYTHON_PREFERENCE=only-system \
        UV_PYTHON_DOWNLOADS=never \
          ${pkgs.uv}/bin/uv venv \
            --python "${pkgs.python3}/bin/python3" \
            "$TOOL_DIR/venv" && \
        UV_PYTHON="${pkgs.python3}/bin/python3" \
        UV_PYTHON_PREFERENCE=only-system \
        UV_PYTHON_DOWNLOADS=never \
          ${pkgs.uv}/bin/uv pip install \
            --python "$TOOL_DIR/venv/bin/python" \
            --compile-bytecode \
            --prerelease=allow \
            "holmesgpt==$DESIRED_VERSION"
      ) >"$install_log" 2>&1; then
        ${pkgs.coreutils}/bin/cat "$install_log" >&2
        exit 1
      fi

      "${pkgs.python3}/bin/python3" <<'PY'
from pathlib import Path

bash_path = "${pkgs.bash}/bin/bash"
site_packages = Path("${holmesToolDir}/venv/lib/python3.13/site-packages/holmes")

for path in site_packages.rglob("*"):
    if not path.is_file():
        continue
    if path.suffix not in {".py", ".yaml", ".yml", ".jinja2"}:
        continue
    text = path.read_text()
    updated = (
        text.replace('executable="/bin/bash"', f'executable="{bash_path}"')
            .replace("Ensure /bin/bash is available.", f"Ensure {bash_path} is available.")
            .replace("#!/bin/bash", f"#!{bash_path}")
    )
    if updated != text:
        path.write_text(updated)
PY

      printf '%s\n' "$INSTALL_STAMP" > "$VERSION_FILE"
    }

    if [ ! -x "$REAL_HOLMES" ] || [ ! -f "$VERSION_FILE" ] || [ "$(${pkgs.coreutils}/bin/cat "$VERSION_FILE")" != "$INSTALL_STAMP" ]; then
      install_holmes
    fi

    export LD_LIBRARY_PATH="${runtimeLibraryPath}:''${LD_LIBRARY_PATH:-}"
    export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
    export DBUS_SESSION_BUS_ADDRESS="''${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
    export SSH_AUTH_SOCK="''${SSH_AUTH_SOCK:-${config.home.homeDirectory}/.1password/agent.sock}"
    export OP_BIOMETRIC_UNLOCK_ENABLED="''${OP_BIOMETRIC_UNLOCK_ENABLED:-true}"
    export OP_DEVICE="''${OP_DEVICE:-Linux}"
    export MODEL="''${MODEL:-${defaultModel}}"
    export PYTHONWARNINGS="''${PYTHONWARNINGS:-ignore}"

    case "''${1:-}" in
      -h|--help|help|version|--version)
        exec "$REAL_HOLMES" "$@"
        ;;
    esac

    if [ -n "''${ANTHROPIC_API_KEY:-}" ]; then
      exec "$REAL_HOLMES" "$@"
    fi

    anthropic_api_key=""
    if anthropic_api_key="$(${pkgs._1password-cli}/bin/op read '${anthropicApiKeyRef}' 2>/dev/null)"; then
      umask 077
      printf '%s\n' "$anthropic_api_key" > "${anthropicApiKeyCache}"
    elif [ -s "${anthropicApiKeyCache}" ]; then
      anthropic_api_key="$(${pkgs.coreutils}/bin/cat "${anthropicApiKeyCache}")"
    else
      echo "[ERROR] could not read secret '${anthropicApiKeyRef}' and no cached fallback exists" >&2
      echo "Try running: op read ${anthropicApiKeyRef} >/dev/null" >&2
      exit 1
    fi

    export ANTHROPIC_API_KEY="$anthropic_api_key"

    exec "$REAL_HOLMES" "$@"
  '';

  holmesK9sRun = pkgs.writeShellScriptBin "holmes-k9s-run" ''
    set -euo pipefail

    prompt="$*"
    if [ -z "$prompt" ]; then
      echo "holmes-k9s-run: missing prompt" >&2
      exit 1
    fi

    temp_kubeconfig=""
    cleanup() {
      if [ -n "$temp_kubeconfig" ] && [ -e "$temp_kubeconfig" ]; then
        ${pkgs.coreutils}/bin/rm -f "$temp_kubeconfig"
      fi
    }
    trap cleanup EXIT

    if [ -n "''${CONTEXT:-}" ]; then
      current_context="$(${pkgs.kubectl}/bin/kubectl config current-context 2>/dev/null || true)"

      if [ "$current_context" != "$CONTEXT" ]; then
        temp_kubeconfig="$(${pkgs.coreutils}/bin/mktemp)"
        ${pkgs.kubectl}/bin/kubectl config view --raw > "$temp_kubeconfig"
        KUBECONFIG="$temp_kubeconfig" ${pkgs.kubectl}/bin/kubectl config use-context "$CONTEXT" >/dev/null
        export KUBECONFIG="$temp_kubeconfig"
      fi
    fi

    set +e
    "${holmesWrapper}/bin/holmes" ask \
      --no-interactive \
      --no-echo \
      --fast-mode \
      "$prompt"
    status=$?
    set -e

    if ${pkgs.coreutils}/bin/tty -s; then
      printf "\nPress 'q' to exit"
      while :; do
        if ! IFS= read -r -n 1 key < /dev/tty; then
          break
        fi

        if [ "$key" = "q" ]; then
          break
        fi
      done
    fi

    exit "$status"
  '';

  holmesK9sCustom = pkgs.writeShellScriptBin "holmes-k9s-custom" ''
    set -euo pipefail

    question_file="$(${pkgs.coreutils}/bin/mktemp)"
    trap '${pkgs.coreutils}/bin/rm -f "$question_file"' EXIT

    resource_name="''${RESOURCE_NAME:-selected resource}"
    prompt_name="''${NAME:-$resource_name}"
    namespace="''${NAMESPACE:-default}"

    cat > "$question_file" <<EOF
# Edit the prompt below, save, and quit to run HolmesGPT.
# Lines starting with # are ignored.
why is $prompt_name of $resource_name in -n $namespace not working as expected
EOF

    editor="''${EDITOR:-${pkgs.neovim}/bin/nvim}"
    "$editor" "$question_file"

    user_input="$(
      ${pkgs.gnused}/bin/sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' "$question_file" \
      | ${pkgs.coreutils}/bin/tr '\n' ' ' \
      | ${pkgs.gnused}/bin/sed 's/[[:space:]]\\+/ /g; s/^ //; s/ $//'
    )"

    if [ -z "$user_input" ]; then
      exit 0
    fi

    exec "${holmesK9sRun}/bin/holmes-k9s-run" "$user_input"
  '';
in
lib.mkIf pkgs.stdenv.isLinux {
  home.packages = [
    holmesWrapper
    holmesK9sRun
    holmesK9sCustom
  ];

  xdg.configFile."k9s/plugins.yaml".text = ''
    plugins:
      holmesgpt:
        shortCut: Shift-H
        description: Ask HolmesGPT
        scopes:
          - all
        command: ${pkgs.bash}/bin/bash
        background: false
        confirm: false
        args:
          - -lc
          - 'exec ${holmesK9sRun}/bin/holmes-k9s-run "why is $NAME of $RESOURCE_NAME in -n $NAMESPACE not working as expected"'

      custom-holmesgpt:
        shortCut: Shift-Q
        description: Custom HolmesGPT Ask
        scopes:
          - all
        command: ${pkgs.bash}/bin/bash
        background: false
        confirm: false
        args:
          - -lc
          - 'exec ${holmesK9sCustom}/bin/holmes-k9s-custom'
  '';
}
