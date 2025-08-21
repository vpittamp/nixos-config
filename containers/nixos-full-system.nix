{ pkgs, lib, homeModule, systemPackages }:

let
  # Import home configuration and extract settings
  homeConfig = homeModule { config = {}; inherit pkgs lib; };
  
  # Extract packages and configurations from home-manager
  homePackages = homeConfig.home.packages;
  bashAliases = homeConfig.programs.bash.shellAliases;
  bashInitExtra = homeConfig.programs.bash.initExtra;
  bashSessionVars = homeConfig.programs.bash.sessionVariables;
  seshConfigContent = homeConfig.xdg.configFile."sesh/sesh.toml".text;
  gitConfig = homeConfig.programs.git;
  starshipSettings = homeConfig.programs.starship.settings;
  tmuxExtraConfig = homeConfig.programs.tmux.extraConfig;
  
  # Create initialization script
  initScript = pkgs.writeScriptBin "container-init" ''
    #!${pkgs.bashInteractive}/bin/bash
    set -e
    
    echo "🚀 Initializing NixOS System Container"
    
    # Create user if running as root (first time setup)
    if [ "$EUID" -eq 0 ]; then
      # Set up sudoers if it doesn't exist or is empty
      if [ ! -f /etc/sudoers ] || [ ! -s /etc/sudoers ]; then
        echo "Setting up sudoers..."
        cat > /etc/sudoers << 'SUDOERS_EOF'
    Defaults env_reset
    root ALL=(ALL:ALL) ALL
    %wheel ALL=(ALL:ALL) ALL
    vpittamp ALL=(ALL) NOPASSWD:ALL
    SUDOERS_EOF
      fi
      
      # Create vpittamp user if it doesn't exist
      if ! id -u vpittamp >/dev/null 2>&1; then
        echo "Creating user vpittamp..."
        groupadd -g 1000 vpittamp || true
        useradd -u 1000 -g 1000 -m -d /home/vpittamp -s /bin/bash vpittamp || true
      fi
      
      # Set up as vpittamp user
      export HOME=/home/vpittamp
      export USER=vpittamp
      
      # Create config directories
      mkdir -p $HOME/.config/{tmux,sesh,nvim,nix,starship}
      mkdir -p $HOME/.local/state/nix/profiles
      mkdir -p $HOME/.cache
      
      # Switch to vpittamp user after setup
      SWITCH_USER=true
    else
      # Already running as user
      export HOME=/home/vpittamp
      export USER=vpittamp
      
      # Create config directories
      mkdir -p $HOME/.config/{tmux,sesh,nvim,nix,starship}
      mkdir -p $HOME/.local/state/nix/profiles
      mkdir -p $HOME/.cache
      SWITCH_USER=false
    fi
    
    # Write bash configuration from home-manager
    cat > $HOME/.bashrc << 'BASHRC_EOF'
    # Environment variables from home-manager
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}='${toString v}'") bashSessionVars)}
    
    # Aliases from home-manager
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "alias ${k}='${v}'") bashAliases)}
    
    # Additional bash configuration
    ${bashInitExtra}
    BASHRC_EOF
    
    # Write tmux configuration
    cat > $HOME/.config/tmux/tmux.conf << 'TMUX_EOF'
    # Generated from home-manager configuration
    set -g prefix \`
    set -g base-index 1
    set -g history-limit 10000
    set -g mode-keys vi
    set -g mouse on
    set -g terminal-overrides ',*256col*:Tc'
    
    ${tmuxExtraConfig}
    TMUX_EOF
    
    # Write sesh configuration
    cat > $HOME/.config/sesh/sesh.toml << 'SESH_EOF'
    ${seshConfigContent}
    SESH_EOF
    
    # Git configuration from home-manager
    git config --global user.name "${gitConfig.userName}"
    git config --global user.email "${gitConfig.userEmail}"
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "git config --global alias.${k} '${v}'") (gitConfig.aliases or {}))}
    
    # Starship configuration
    cat > $HOME/.config/starship/starship.toml << 'STARSHIP_EOF'
    ${builtins.toJSON starshipSettings}
    STARSHIP_EOF
    
    # Ensure ownership
    if [ "$EUID" -eq 0 ]; then
      chown -R vpittamp:vpittamp $HOME
    fi
    
    # Source bashrc and start bash
    cd $HOME
    if [ "$SWITCH_USER" = "true" ]; then
      exec su - vpittamp -c "${pkgs.bashInteractive}/bin/bash --rcfile $HOME/.bashrc"
    else
      exec ${pkgs.bashInteractive}/bin/bash --rcfile $HOME/.bashrc
    fi
  '';
in
pkgs.dockerTools.buildLayeredImage {
  name = "nixos-full-system";
  tag = "latest";
  created = "now";
  maxLayers = 128;
  
  contents = pkgs.buildEnv {
    name = "nixos-system-env";
    paths = with pkgs; [
      # Core system utilities
      bashInteractive
      coreutils
      cacert
      shadow
      su
      sudo
      ncurses
      findutils
      gnused
      gnutar
      gzip
      xz
      which
      file
      
      # Include Git for configuration
      git
      
      # The initialization script
      initScript
    ] ++ homePackages ++ systemPackages;
    
    pathsToLink = [ "/bin" "/etc" "/lib" "/share" "/sbin" ];
  };
  
  # Create essential system files
  extraCommands = ''
    # Create /etc directory structure
    mkdir -p etc
    
    # Create minimal passwd file with root user
    cat > etc/passwd << 'EOF'
    root:x:0:0:root:/root:/bin/bash
    nobody:x:65534:65534:nobody:/nonexistent:/bin/false
    EOF
    
    # Create minimal group file
    cat > etc/group << 'EOF'
    root:x:0:
    wheel:x:1:
    users:x:100:
    nobody:x:65534:
    EOF
    
    # Create shadow file (empty passwords)
    cat > etc/shadow << 'EOF'
    root:!:19000:0:99999:7:::
    nobody:!:19000:0:99999:7:::
    EOF
    
    # Create basic structure
    mkdir -p etc/pam.d
    mkdir -p home
    mkdir -p root
    mkdir -p tmp
    chmod 1777 tmp
    mkdir -p var/tmp
    chmod 1777 var/tmp
  '';
  
  config = {
    User = "root";
    WorkingDir = "/root";
    
    Env = [
      "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
      "HOME=/root"
      "USER=root"
      "TERM=xterm-256color"
      "EDITOR=nvim"
      "VISUAL=nvim"
      "PAGER=less"
      "LESS=-R"
      "LANG=en_US.UTF-8"
      "LC_ALL=en_US.UTF-8"
      "NIX_PAGER=cat"
    ];
    
    Cmd = [ "/bin/container-init" ];
    
    Volumes = {
      "/workspace" = {};
    };
    
    Labels = {
      "org.opencontainers.image.source" = "https://github.com/vpittamp/nixos-config";
      "org.opencontainers.image.description" = "Complete NixOS development environment from flake";
      "org.opencontainers.image.authors" = "Vinod Pittampalli <vinod@pittampalli.com>";
    };
  };
}