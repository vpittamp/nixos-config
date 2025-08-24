#!/bin/bash

# github codespaces fixes
if [ "${CODESPACES}" = true ]; then
  # vscode codespaces set default permissions on /tmp. These will
  # produce invalid permissions on files built with nix. This fix
  # removes default permissions set on /tmp
  sudo setfacl --remove-default /tmp
fi

# Activate NixOS configuration if requested
if [ "${NIXOS_CONFIG_ACTIVATE}" = "true" ] && [ -f "/usr/local/bin/nixos-activate" ]; then
  echo "Activating NixOS configuration..."
  /usr/local/bin/nixos-activate || echo "Warning: NixOS activation had issues but continuing..."
fi

if [ ! -z "${PRELOAD_EXTENSIONS}" ]; then
  ext-preloader &
fi

if [ $# -eq 0 ]; then
  while :; do sleep 2073600; done
else
  "$@" &
fi

wait -n
