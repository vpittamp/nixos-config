#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: connect-incus-gui.sh [options]

Create an SSH tunnel from this machine to a VM GUI (WayVNC) running on ryzen.
The script can auto-start the VM and waits for DHCP + VNC readiness.

Options:
  --ryzen-host <ssh-target>   SSH host for ryzen (default: vpittamp@ryzen)
  --vm <name>                 Incus VM name on ryzen (default: nixosvm-debug)
  --vm-vnc-port <port>        VNC port inside VM (default: 5900)
  --local-port <port>         Local forwarded port (default: 5900)
  --no-start                  Do not auto-start VM
  --open                      Open local VNC viewer after tunnel starts
  -h, --help                  Show this help

Examples:
  ./scripts/connect-incus-gui.sh
  ./scripts/connect-incus-gui.sh --vm nixosvm --local-port 5905
  ./scripts/connect-incus-gui.sh --ryzen-host vpittamp@192.168.1.50 --open
USAGE
}

RYZEN_HOST="${RYZEN_HOST:-vpittamp@ryzen}"
VM_NAME="${VM_NAME:-nixosvm-debug}"
VM_VNC_PORT="${VM_VNC_PORT:-5900}"
LOCAL_PORT="${LOCAL_PORT:-5900}"
AUTO_START=1
OPEN_VIEWER=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ryzen-host)
      RYZEN_HOST="$2"
      shift 2
      ;;
    --vm)
      VM_NAME="$2"
      shift 2
      ;;
    --vm-vnc-port)
      VM_VNC_PORT="$2"
      shift 2
      ;;
    --local-port)
      LOCAL_PORT="$2"
      shift 2
      ;;
    --no-start)
      AUTO_START=0
      shift
      ;;
    --open)
      OPEN_VIEWER=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if ! [[ "$VM_VNC_PORT" =~ ^[0-9]+$ && "$LOCAL_PORT" =~ ^[0-9]+$ ]]; then
  echo "Ports must be numeric." >&2
  exit 1
fi

SSH_OPTS=(
  -o ConnectTimeout=8
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=3
  -o StrictHostKeyChecking=accept-new
)

remote_cmd() {
  ssh "${SSH_OPTS[@]}" "$RYZEN_HOST" "$@"
}

vm_state() {
  remote_cmd "sudo incus info \"$VM_NAME\" 2>/dev/null | awk '/^Status:/ {print \$2; exit}'"
}

resolve_vm_ip() {
  remote_cmd "sudo incus list --format csv -c ns4 | awk -F, -v vm=\"$VM_NAME\" '\$1==vm{print \$3; exit}' | awk '{print \$1; exit}'"
}

wait_for_ip() {
  local ip=""
  local i
  for i in $(seq 1 40); do
    ip="$(resolve_vm_ip || true)"
    if [[ -n "$ip" ]]; then
      printf '%s\n' "$ip"
      return 0
    fi
    sleep 2
  done
  return 1
}

wait_for_vnc() {
  local ip="$1"
  local i
  for i in $(seq 1 40); do
    if remote_cmd "nc -zw2 \"$ip\" \"$VM_VNC_PORT\" >/dev/null 2>&1"; then
      return 0
    fi
    sleep 2
  done
  return 1
}

echo "[incus-gui] ryzen: $RYZEN_HOST"
echo "[incus-gui] vm:    $VM_NAME"

if (( AUTO_START )); then
  state="$(vm_state || true)"
  if [[ "$state" != "RUNNING" ]]; then
    echo "[incus-gui] Starting VM: $VM_NAME"
    remote_cmd "sudo incus start \"$VM_NAME\""
  fi
fi

echo "[incus-gui] Waiting for VM IP..."
VM_IP="$(wait_for_ip || true)"
if [[ -z "$VM_IP" ]]; then
  echo "[incus-gui] Failed to resolve VM IPv4 address for $VM_NAME." >&2
  exit 1
fi
echo "[incus-gui] VM IP: $VM_IP"

echo "[incus-gui] Waiting for VNC on ${VM_IP}:${VM_VNC_PORT}..."
if ! wait_for_vnc "$VM_IP"; then
  echo "[incus-gui] VNC not reachable on ${VM_IP}:${VM_VNC_PORT}." >&2
  exit 1
fi

if ss -H -tuln "sport = :${LOCAL_PORT}" | grep -q .; then
  echo "[incus-gui] Local port ${LOCAL_PORT} is already in use." >&2
  echo "[incus-gui] Re-run with --local-port <free-port>." >&2
  exit 1
fi

echo "[incus-gui] Tunnel ready target: localhost:${LOCAL_PORT} -> ${VM_IP}:${VM_VNC_PORT}"
if (( OPEN_VIEWER )); then
  if command -v vncviewer >/dev/null 2>&1; then
    ssh "${SSH_OPTS[@]}" -f -N -L "${LOCAL_PORT}:${VM_IP}:${VM_VNC_PORT}" "$RYZEN_HOST"
    sleep 1
    exec vncviewer "127.0.0.1:${LOCAL_PORT}"
  else
    echo "[incus-gui] --open requested but 'vncviewer' is not installed." >&2
    exit 1
  fi
fi

echo "[incus-gui] Connect your VNC client to: 127.0.0.1:${LOCAL_PORT}"
echo "[incus-gui] Press Ctrl+C to close tunnel."
exec ssh "${SSH_OPTS[@]}" -N -L "${LOCAL_PORT}:${VM_IP}:${VM_VNC_PORT}" "$RYZEN_HOST"
