# User-level packages safe for home-manager
# These are all from nixpkgs and don't require special build permissions
# Safe to use in restricted container environments
{ pkgs, lib, inputs ? { }, ... }:

let
  # IDP Builder - x86_64 only
  idpbuilder = pkgs.callPackage ../packages/idpbuilder.nix {
    idpbuilderSrc = inputs.idpbuilder-src or null;
  };

  # goose-desktop removed 2026-08-23 (slimming, ~399 MiB); state last written
  # 2026-03-24. Definition remains at ../packages/goose-desktop.nix if wanted back.

  # GitHub Copilot - agent-native desktop app (github/app AppImage; x86_64 + aarch64).
  # Restored 2026-08-24 at 1.1.12 by request, after the 2026-08-23 slimming pass
  # removed it as unused. See packages/github-copilot.nix for the NixOS quirks
  # (notably: disable the app's "Use bundled git" experiment — its bundled git needs
  # libcurl-gnutls.so.4, which NixOS does not ship).
  github-copilot = pkgs.callPackage ../packages/github-copilot.nix { };

  # Kimi Code CLI (`kimi`) - MoonshotAI coding agent, packaged from the
  # self-contained npm bundle (@moonshot-ai/kimi-code). See packages/kimi-code.nix.
  kimi-code = pkgs.callPackage ../packages/kimi-code.nix { };

  # talosctl pinned to v1.13.x — nixpkgs lags at 1.12.x (as of Jan 2026) and
  # the ryzen Talos OS + Kubernetes 1.36 upgrade flow needs v1.13+ (pruning
  # support + 1.36 awareness). Remove this override once nixpkgs catches up.
  talosctl-1-13 = pkgs.callPackage ../packages/talosctl-1-13.nix { };

  # dapr-cli pinned to 1.17.x matching the Dapr runtime installed in
  # PittampalliOrg/stacks (runtime 1.17.7). Nixpkgs currently ships 1.16.4.
  # See packages/dapr-cli.nix for the rationale and Go-toolchain constraints.
  dapr-cli = pkgs.callPackage ../packages/dapr-cli.nix { };

  # Latest dlvhdr GitHub TUIs. These are local pins because the main nixpkgs
  # input currently lags gh-dash/diffnav and does not package gh-enhance.
  gh-dash = pkgs.callPackage ../packages/gh-dash.nix { };
  gh-enhance = pkgs.callPackage ../packages/gh-enhance.nix { };
  diffnav = pkgs.callPackage ../packages/diffnav.nix { };

  # Herdr terminal multiplexer for AI coding agents, sourced from its flake.
  # Current Codex Nix builds expose the long-running interactive process as
  # codex-raw, so carry a small compatibility patch until upstream recognizes
  # that binary name as Codex.
  herdr = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ../patches/herdr-codex-raw-agent-detection.patch
    ];
  });

  # Hunk review-first terminal diff viewer for agent-authored changesets,
  # sourced from its upstream flake (built from source via bun2nix).
  hunk = inputs.hunk.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Text editors and IDEs (from nixpkgs)
  editors = with pkgs; [
    # vim is managed by programs.vim in home-manager
    # neovim is managed by programs.neovim in home-manager
    # vscode is provided at system level via wrapper
  ];

  # Terminal tools and utilities
  terminalTools = with pkgs; [
    tmux
    # sesh is managed by programs.sesh in home-manager
    zoxide
    fzf
    ripgrep
    fd
    bat
    lazydocker
    eza
    direnv
    stow
    tree
    htop
    btop
    ncdu
    glow
    jq
    yq
    curl
    wget
    gum
    tailscale # VPN CLI tool
    chafa # Terminal image viewer for fzf previews
    television # TUI fuzzy finder with built-in channels
    glib # For gio command (desktop file launcher and file operations)
    catt # Chromecast CLI tool for direct IP streaming
    libnotify # Desktop notification helper (notify-send)
  ];

  # AI and LLM tools
  aiTools = [
    herdr
    hunk # Hunk review-first terminal diff viewer (upstream flake)
    github-copilot # GitHub Copilot agent-native desktop app (custom package)
    kimi-code # Kimi Code CLI (`kimi`) — MoonshotAI coding agent (custom package)
  ] ++ (with pkgs; [
    agent-browser # Vercel Labs browser automation CLI for AI agents (Rust, CDP)
    openai # OpenAI Python CLI
    # goose-cli removed 2026-08-23 (slimming, ~455 MiB alongside goose-desktop's 399 MiB);
    # ~/.config/goose last written 2026-03-24.
    # playwright-test removed 2026-08-23 (slimming, ~1.11 GiB — the CLI drags in bundled
    # chromium/firefox/webkit/headless-shell builds). The @playwright/mcp server in
    # home-modules/tools/vscode.nix is fetched by npx and does not need this package.
    # Note: gitingest is run on-demand via: uvx gitingest <repo-url>
    # This ensures we always use the latest version without pre-installation
    # See /etc/nixos/.claude/commands/gitingest.md for usage
  ]);

  # Shell enhancements
  shellTools = with pkgs; [
    starship
    zsh
    bash
    fish
  ];

  # Python testing environment (Feature 039)
  # REMOVED: Merged into sharedPythonEnv in python-environment.nix to prevent buildEnv conflicts
  # All testing packages (pytest, pytest-asyncio, pytest-cov, click, rich, pydantic, i3ipc, psutil)
  # are now available via the shared Python environment

  # Language servers and development tools (from nixpkgs)
  languageServers = with pkgs; [
    # TypeScript/JavaScript
    typescript-language-server
    prettier
    eslint

    # Python
    pyright
    black
    ruff
    # Feature 039: Python testing environment now provided by sharedPythonEnv (python-environment.nix)

    # Nix
    nil
    nixpkgs-fmt

    # Go
    gopls

    # Rust
    rust-analyzer
    # rustfmt removed 2026-08-23 (slimming): it was the last thing referencing the
    # 1.0 GiB rustc-1.95.0 closure after rustc/cargo left systemPackages, so keeping it
    # would have undone most of that saving. rust-analyzer above is standalone (~93 MiB)
    # and `cargo fmt` inside a Rust devshell is the right home for formatting.
  ];

  # Package managers (from nixpkgs)
  packageManagers = with pkgs; [
    yarn
    pnpm
    uv # Fast Python package installer and resolver (replaces poetry)
  ];

  # File managers
  fileManagers = with pkgs; [
    # Terminal-based
    yazi
    ranger
    lf

    # GUI
    xfce.thunar        # Lightweight GTK file manager (popular for i3)
    xfce.thunar-volman # Thunar volume manager
    xfce.thunar-archive-plugin # Archive support for Thunar
    arandr             # GUI for xrandr (display configuration)
  ];

  # Git tools (from nixpkgs, no custom builds)
  gitTools = with pkgs; [
    git-lfs
    git-crypt
    delta
    diff-so-fancy
    lazygit
    gh-dash
    gh-enhance
    diffnav
    gittyup # GUI git client (Qt-based, lightweight alternative to GitKraken)
    # gitkraken removed 2026-08-23 (slimming, ~636 MiB): last used 2026-06-02, and
    # gittyup above plus lazygit already cover the GUI/TUI git workflow.
  ];

  # Kubernetes and cloud tools
  kubernetesTools = with pkgs; [
    kubectl # Kubernetes CLI
    kubernetes-helm # Helm package manager for Kubernetes
    k9s # Terminal UI for Kubernetes
    # talosctl pinned to v1.13.x via ../packages/talosctl-1-13.nix
    # (nixpkgs stuck at 1.12.x as of Jan 2026; 1.13+ required for
    # K8s 1.36 upgrade + pruning support on ryzen).
    skaffold # Local Kubernetes development tool
    talosctl-1-13 # CLI for Talos Linux Kubernetes OS (1.13.x pin)
    dapr-cli # CLI for Dapr distributed runtime (1.17.x pin, matches stacks runtime)
  ] ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [
    idpbuilder # IDP builder tool (x86_64 only)
  ];

  # Cloud tools (for containers/Codespaces)
  # azure-cli-bin removed 2026-08-23 (slimming, ~1.88 GiB — the CLI plus its whole
  # azure-mgmt-* SDK tree). The fleet moved off Azure Key Vault to 1Password
  # (ClusterSecretStore onepassword-store, onepasswordSDK provider; no azurekv store
  # exists on hub or dev), and the last runtime consumer — the ryzen host-passthrough
  # step in home-modules/tools/fleet-kubeconfigs.nix — went with the decommissioned
  # ryzen Talos cluster. Scripts under scripts/ that still shell out to `az`
  # (langfuse-auth.sh, sync-jwks-to-azure.sh, setup-1password-entra-sso.sh,
  # deploy-nixos-ssh.sh) need it back on PATH first; `nix shell nixpkgs#azure-cli`
  # covers a one-off run.
  cloudTools = [ ];

  # Documentation and help
  documentation = with pkgs; [
    tldr
    man-pages
    man-pages-posix
  ];

  # Nix helper tools
  nixTools = with pkgs; [
    nh # Yet another nix cli helper
    nix-output-monitor # Prettier nix build output
    nixpkgs-fmt # Nix code formatter
    alejandra # Alternative Nix formatter
    nix-tree # Visualize Nix store dependencies
    nix-prefetch-git # Prefetch git repositories
  ];

in
{
  # Export categorized packages
  editors = editors;
  terminal = terminalTools;
  shell = shellTools;
  languageServers = languageServers;
  packageManagers = packageManagers;
  fileManagers = fileManagers;
  git = gitTools;
  kubernetes = kubernetesTools;
  cloud = cloudTools;
  docs = documentation;
  nix = nixTools;
  ai = aiTools;

  # Common package sets
  essential = terminalTools ++ shellTools ++ nixTools ++ [
    # vim handled by programs.vim
    pkgs.git-lfs
    pkgs.tldr
    pkgs.yazi # Terminal file manager
    pkgs.yarn # JavaScript package manager
  ];

  development = terminalTools ++ shellTools ++ editors ++
    languageServers ++ packageManagers ++ gitTools ++ kubernetesTools ++ cloudTools ++ nixTools ++ aiTools;

  # All user packages
  all = terminalTools ++ shellTools ++ editors ++
    languageServers ++ packageManagers ++ fileManagers ++
    gitTools ++ kubernetesTools ++ cloudTools ++ documentation ++ nixTools ++ aiTools;

  # Minimal for testing
  minimal = with pkgs; [
    # vim handled by programs.vim
    tmux
    git
    curl
    jq
    fzf
    ripgrep
  ];
}
