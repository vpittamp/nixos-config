#!/usr/bin/env bash
# check-input-usage.sh - Verify if a flake input is safe to remove
# Usage: ./check-input-usage.sh <input-name>
# Example: ./check-input-usage.sh plasma-manager

set -euo pipefail

INPUT_NAME="${1:-}"

if [[ -z "$INPUT_NAME" ]]; then
  echo "Usage: $0 <input-name>"
  echo "Example: $0 plasma-manager"
  exit 1
fi

echo "Checking usage of input: $INPUT_NAME"
echo "======================================="

# 1. Search all Nix files
echo -e "\n1. Searching Nix files..."
FOUND_NIX=0
if rg "inputs\.$INPUT_NAME" --type nix 2>/dev/null; then
  echo "   ⚠️  Found references in Nix files"
  FOUND_NIX=1
else
  echo "   ✅ No direct references in Nix files"
fi

# 2. Check archived code
echo -e "\n2. Checking archived code..."
FOUND_ARCHIVED=0
if rg "$INPUT_NAME" archived/ 2>/dev/null; then
  echo "   ⚠️  Found in archived code (may be safe to ignore)"
  FOUND_ARCHIVED=1
else
  echo "   ✅ Not in archived code"
fi

# 3. Check flake.lock
echo -e "\n3. Checking flake.lock..."
FOUND_LOCK=0
if cat flake.lock | jq -e ".nodes.\"$INPUT_NAME\"" >/dev/null 2>&1; then
  echo "   ⚠️  Input is locked in flake.lock"
  FOUND_LOCK=1

  # Show input details
  echo "   Input details:"
  cat flake.lock | jq ".nodes.\"$INPUT_NAME\".locked" 2>/dev/null || true
else
  echo "   ✅ Not in flake.lock"
fi

# 4. Test configurations
echo -e "\n4. Testing configurations (dry-run)..."
EVAL_ERRORS=0
for config in hetzner-sway m1; do
  echo "   Testing: $config"
  if nix eval --raw .#nixosConfigurations.$config.config.networking.hostName 2>&1 | grep -q "error"; then
    echo "     ❌ Evaluation failed"
    EVAL_ERRORS=$((EVAL_ERRORS + 1))
  else
    HOSTNAME=$(nix eval --raw .#nixosConfigurations.$config.config.networking.hostName 2>/dev/null || echo "unknown")
    echo "     ✅ Evaluation succeeded (hostname: $HOSTNAME)"
  fi
done

# 5. Check packages
echo -e "\n5. Checking package usage..."
FOUND_PACKAGES=0
if command -v nix &> /dev/null; then
  for system in x86_64-linux aarch64-linux; do
    echo "   Checking system: $system"
    PACKAGES=$(nix eval --json .#packages.$system --apply 'builtins.attrNames' 2>/dev/null | jq -r '.[]' || echo "")

    for pkg in $PACKAGES; do
      if nix show-derivation .#packages.$system.$pkg 2>/dev/null | grep -q "$INPUT_NAME"; then
        echo "     ⚠️  Used in package: $pkg (system: $system)"
        FOUND_PACKAGES=$((FOUND_PACKAGES + 1))
      fi
    done
  done

  if [[ $FOUND_PACKAGES -eq 0 ]]; then
    echo "   ✅ Not used in any packages"
  fi
else
  echo "   ⚠️  Nix not found, skipping package check"
fi

# 6. Check home configurations
echo -e "\n6. Checking Home Manager configurations..."
FOUND_HOME=0
HOME_CONFIGS=$(nix eval --json .#homeConfigurations --apply 'builtins.attrNames' 2>/dev/null | jq -r '.[]' || echo "")

for config in $HOME_CONFIGS; do
  echo "   Testing: $config"
  if nix eval .#homeConfigurations.$config.config.home.username 2>&1 | grep -q "$INPUT_NAME"; then
    echo "     ⚠️  Possibly used in home config: $config"
    FOUND_HOME=$((FOUND_HOME + 1))
  else
    echo "     ✅ Not directly used in home config"
  fi
done

# 7. Summary
echo -e "\n======================================="
echo "SUMMARY for input: $INPUT_NAME"
echo "======================================="

SAFE_TO_REMOVE=true

if [[ $FOUND_NIX -gt 0 ]] && [[ $FOUND_ARCHIVED -eq 0 ]]; then
  echo "❌ ACTIVE NIX REFERENCES: Input is used in active configurations"
  SAFE_TO_REMOVE=false
elif [[ $FOUND_NIX -gt 0 ]] && [[ $FOUND_ARCHIVED -gt 0 ]]; then
  echo "⚠️  NIX REFERENCES: Only in archived code (likely safe to remove)"
fi

if [[ $FOUND_LOCK -eq 0 ]]; then
  echo "✅ NOT IN FLAKE.LOCK: Input not currently locked"
else
  echo "⚠️  IN FLAKE.LOCK: Input is locked (expected if declared)"
fi

if [[ $EVAL_ERRORS -gt 0 ]]; then
  echo "❌ EVALUATION ERRORS: Configurations failed to evaluate (input may be needed)"
  SAFE_TO_REMOVE=false
else
  echo "✅ EVALUATION SUCCESS: All configurations evaluate without errors"
fi

if [[ $FOUND_PACKAGES -gt 0 ]]; then
  echo "⚠️  PACKAGE USAGE: Input used in $FOUND_PACKAGES package(s)"
  echo "   (Safe to remove if not building these packages)"
fi

if [[ $FOUND_HOME -gt 0 ]]; then
  echo "⚠️  HOME CONFIG USAGE: Input may be used in home configurations"
fi

echo ""
if [[ "$SAFE_TO_REMOVE" == "true" ]]; then
  echo "✅ RECOMMENDATION: Input '$INPUT_NAME' appears SAFE TO REMOVE"
  echo ""
  echo "Next steps:"
  echo "  1. Comment out input in flake.nix"
  echo "  2. Run: nix flake lock --update-input $INPUT_NAME"
  echo "  3. Test: nix flake check"
  echo "  4. Test: sudo nixos-rebuild dry-build --flake .#<config>"
else
  echo "❌ RECOMMENDATION: Input '$INPUT_NAME' is ACTIVELY USED - DO NOT REMOVE"
  echo ""
  echo "This input is required for your active configurations."
fi

echo "======================================="
