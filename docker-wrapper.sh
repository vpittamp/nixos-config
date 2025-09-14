#!/usr/bin/env bash
# Docker Desktop wrapper script for NixOS WSL2
exec sudo DOCKER_HOST=unix:///mnt/wsl/docker-desktop/shared-sockets/guest-services/docker.proxy.sock /mnt/wsl/docker-desktop/cli-tools/usr/bin/docker "$@"
