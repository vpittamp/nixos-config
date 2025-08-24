FROM nixos-devcontainer:latest

# Set user UID/GID to match host user if needed
ARG USER_UID=1000
ARG USER_GID=1000
ARG USERNAME=code

# Install additional system packages for Backstage development
USER root
RUN apt-get update && apt-get install -y \
    postgresql-client \
    build-essential \
    python3 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Switch to code user for following operations
USER ${USERNAME}

# Pre-create directories for better caching and VS Code
RUN mkdir -p /home/${USERNAME}/.cache/yarn \
    && mkdir -p /home/${USERNAME}/.npm \
    && mkdir -p /home/${USERNAME}/.config \
    && mkdir -p /home/${USERNAME}/.vscode-server/data/CachedProfilesData/__default__profile__ \
    && touch /home/${USERNAME}/.vscode-server/data/CachedProfilesData/__default__profile__/extensions.builtin.cache

# Set working directory
WORKDIR /workspace

# Add some useful aliases for Backstage development
RUN echo "" >> /home/${USERNAME}/.bashrc && \
    echo "# Backstage development aliases" >> /home/${USERNAME}/.bashrc && \
    echo "alias dev='yarn dev'" >> /home/${USERNAME}/.bashrc && \
    echo "alias build='yarn build'" >> /home/${USERNAME}/.bashrc && \
    echo "alias test='yarn test'" >> /home/${USERNAME}/.bashrc && \
    echo "alias lint='yarn lint'" >> /home/${USERNAME}/.bashrc && \
    echo "alias typecheck='yarn tsc'" >> /home/${USERNAME}/.bashrc && \
    echo "" >> /home/${USERNAME}/.bashrc && \
    echo "# Auto-activate NixOS config on shell start" >> /home/${USERNAME}/.bashrc && \
    echo "if [ -f /usr/local/bin/nixos-activate ] && [ \"\$NIXOS_CONFIG_ACTIVATE\" = \"true\" ]; then" >> /home/${USERNAME}/.bashrc && \
    echo "  /usr/local/bin/nixos-activate 2>/dev/null || true" >> /home/${USERNAME}/.bashrc && \
    echo "fi" >> /home/${USERNAME}/.bashrc