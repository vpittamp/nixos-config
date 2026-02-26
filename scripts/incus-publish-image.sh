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

incus_cmd() {
  if (( USE_SG_INCUS_ADMIN )); then
    local escaped
    escaped="$(printf '%q ' incus "$@")"
    # shellcheck disable=SC2086
    sg incus-admin -c "${escaped% }"
  else
    incus "$@"
  fi
}

USE_SG_INCUS_ADMIN=0
if ! incus info >/dev/null 2>&1; then
  if command -v sg >/dev/null 2>&1 && getent group incus-admin >/dev/null 2>&1; then
    if sg incus-admin -c "incus info >/dev/null 2>&1"; then
      USE_SG_INCUS_ADMIN=1
      echo "[incus-image] Using sg incus-admin for Incus access"
    else
      echo "Cannot access Incus daemon. Run: newgrp incus-admin (or re-login)." >&2
      exit 1
    fi
  else
    echo "Cannot access Incus daemon and incus-admin group fallback is unavailable." >&2
    exit 1
  fi
fi

echo "[incus-image] Building bundle: ${FLAKE_ATTR}"
BUILD_LINK="$(mktemp -u /tmp/incus-bundle.XXXXXX)"
cleanup() {
  rm -f "$BUILD_LINK"
}
trap cleanup EXIT

nix build "$FLAKE_ATTR" --out-link "$BUILD_LINK"
BUNDLE_PATH="$(readlink -f "$BUILD_LINK")"

if [[ -z "$BUNDLE_PATH" || ! -d "$BUNDLE_PATH" ]]; then
  echo "Failed to resolve built bundle path from $BUILD_LINK" >&2
  exit 1
fi

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

import_cmd=(image import "$METADATA_TAR" "$DISK_QCOW2" --alias "$VERSIONED_ALIAS")

if (( DRY_RUN )); then
  echo "[dry-run] incus ${import_cmd[*]}"
  echo "[dry-run] incus image alias delete $STABLE_ALIAS"
  echo "[dry-run] incus image alias create $STABLE_ALIAS <fingerprint>"
  exit 0
fi

if incus_cmd image alias list --format csv | cut -d, -f1 | grep -Fxq "$VERSIONED_ALIAS"; then
  echo "Versioned alias already exists: $VERSIONED_ALIAS" >&2
  echo "Use --version with a new value." >&2
  exit 1
fi

echo "[incus-image] Importing image"
incus_cmd "${import_cmd[@]}"

FINGERPRINT="$(incus_cmd image info "$VERSIONED_ALIAS" | awk '/^Fingerprint:/ {print $2}')"
if [[ -z "$FINGERPRINT" ]]; then
  echo "Failed to resolve fingerprint for alias: $VERSIONED_ALIAS" >&2
  exit 1
fi

echo "[incus-image] Imported fingerprint: $FINGERPRINT"

if incus_cmd image alias list --format csv | cut -d, -f1 | grep -Fxq "$STABLE_ALIAS"; then
  incus_cmd image alias delete "$STABLE_ALIAS"
fi

incus_cmd image alias create "$STABLE_ALIAS" "$FINGERPRINT"

echo "[incus-image] Updated aliases:"
echo "  - $VERSIONED_ALIAS -> $FINGERPRINT"
echo "  - $STABLE_ALIAS -> $FINGERPRINT"
echo
echo "Launch command:"
echo "  incus launch $STABLE_ALIAS <vm-name> --vm"
