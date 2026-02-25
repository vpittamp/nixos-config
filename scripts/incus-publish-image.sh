#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Build and publish the Incus Sway Lite image into local Incus.

Options:
  --stable-alias <name>    Stable alias to maintain (default: nixos-incus-sway-lite)
  --version <value>        Version suffix for immutable alias (default: YYYYMMDD-<gitsha>)
  --flake-attr <attr>      Bundle flake attr to build (default: .#incus-sway-lite-incus-bundle)
  --dry-run                Print commands without executing import/alias updates
  -h, --help               Show this help

Examples:
  $(basename "$0")
  $(basename "$0") --version 20260225-r1
  $(basename "$0") --stable-alias nixos-incus-sway-lite --dry-run
USAGE
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

STABLE_ALIAS="nixos-incus-sway-lite"
FLAKE_ATTR=".#incus-sway-lite-incus-bundle"
DRY_RUN=0
VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stable-alias)
      STABLE_ALIAS="$2"
      shift 2
      ;;
    --version)
      VERSION="$2"
      shift 2
      ;;
    --flake-attr)
      FLAKE_ATTR="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
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

if [[ -z "$VERSION" ]]; then
  DATE_PART="$(date +%Y%m%d)"
  if git rev-parse --short=8 HEAD >/dev/null 2>&1; then
    REV_PART="$(git rev-parse --short=8 HEAD)"
  else
    REV_PART="nogit"
  fi
  VERSION="${DATE_PART}-${REV_PART}"
fi

VERSIONED_ALIAS="${STABLE_ALIAS}-${VERSION}"

echo "[incus-image] Building bundle: ${FLAKE_ATTR}"
BUNDLE_PATH="$(nix build "$FLAKE_ATTR" --print-out-paths --no-link | tail -n1)"

METADATA_TAR="${BUNDLE_PATH}/incus.tar.xz"
DISK_QCOW2="${BUNDLE_PATH}/disk.qcow2"

if [[ ! -f "$METADATA_TAR" ]]; then
  echo "Missing metadata tarball: $METADATA_TAR" >&2
  exit 1
fi

if [[ ! -f "$DISK_QCOW2" ]]; then
  echo "Missing qcow2 image: $DISK_QCOW2" >&2
  exit 1
fi

echo "[incus-image] Bundle path: $BUNDLE_PATH"
echo "[incus-image] Versioned alias: $VERSIONED_ALIAS"
echo "[incus-image] Stable alias:    $STABLE_ALIAS"

import_cmd=(incus image import "$METADATA_TAR" "$DISK_QCOW2" --alias "$VERSIONED_ALIAS")

if (( DRY_RUN )); then
  echo "[dry-run] ${import_cmd[*]}"
  echo "[dry-run] incus image alias delete $STABLE_ALIAS"
  echo "[dry-run] incus image alias create $STABLE_ALIAS <fingerprint>"
  exit 0
fi

if incus image alias list --format csv | cut -d, -f1 | grep -Fxq "$VERSIONED_ALIAS"; then
  echo "Versioned alias already exists: $VERSIONED_ALIAS" >&2
  echo "Use --version with a new value." >&2
  exit 1
fi

echo "[incus-image] Importing image"
"${import_cmd[@]}"

FINGERPRINT="$(incus image info "$VERSIONED_ALIAS" | awk '/^Fingerprint:/ {print $2}')"
if [[ -z "$FINGERPRINT" ]]; then
  echo "Failed to resolve fingerprint for alias: $VERSIONED_ALIAS" >&2
  exit 1
fi

echo "[incus-image] Imported fingerprint: $FINGERPRINT"

if incus image alias list --format csv | cut -d, -f1 | grep -Fxq "$STABLE_ALIAS"; then
  incus image alias delete "$STABLE_ALIAS"
fi

incus image alias create "$STABLE_ALIAS" "$FINGERPRINT"

echo "[incus-image] Updated aliases:"
echo "  - $VERSIONED_ALIAS -> $FINGERPRINT"
echo "  - $STABLE_ALIAS -> $FINGERPRINT"
echo
echo "Launch command:"
echo "  incus launch $STABLE_ALIAS <vm-name> --vm"
