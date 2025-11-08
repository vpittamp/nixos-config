# Dockerfile for Sway Test Framework CI Testing
# Provides a headless Sway environment with Deno for running automated tests

FROM debian:bookworm-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    # Sway and Wayland dependencies
    sway \
    wlroots \
    wayland-protocols \
    xwayland \
    # Graphics and rendering (headless mode)
    mesa-utils \
    libgles2-mesa \
    # Deno dependencies
    curl \
    unzip \
    ca-certificates \
    # IPC and networking
    socat \
    netcat-openbsd \
    # Python for tree-monitor daemon
    python3 \
    python3-pip \
    python3-i3ipc \
    # JSON tools for debugging
    jq \
    # Cleanup
    && rm -rf /var/lib/apt/lists/*

# Install Deno
ENV DENO_INSTALL=/usr/local
RUN curl -fsSL https://deno.land/install.sh | sh && \
    mv /root/.deno/bin/deno /usr/local/bin/deno && \
    chmod +x /usr/local/bin/deno

# Set environment for headless Sway
ENV WLR_BACKENDS=headless \
    WLR_LIBINPUT_NO_DEVICES=1 \
    WAYLAND_DISPLAY=wayland-1 \
    XDG_RUNTIME_DIR=/tmp/runtime

# Create runtime directory
RUN mkdir -p /tmp/runtime && chmod 700 /tmp/runtime

# Copy sway-test framework
WORKDIR /app
COPY . /app/

# Install Python dependencies for tree-monitor daemon
RUN pip3 install --no-cache-dir \
    i3ipc==2.2.1 \
    orjson \
    psutil

# Verify installations
RUN sway --version && \
    deno --version && \
    python3 --version

# Default command runs tests
CMD ["deno", "run", "--allow-all", "src/main.ts", "run", "--ci"]

# Health check: verify Sway can start in headless mode
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD pgrep sway || exit 1

# Metadata
LABEL org.opencontainers.image.title="Sway Test Framework"
LABEL org.opencontainers.image.description="Headless Sway testing environment with Deno"
LABEL org.opencontainers.image.authors="NixOS Configuration"
LABEL org.opencontainers.image.version="1.0.0"
