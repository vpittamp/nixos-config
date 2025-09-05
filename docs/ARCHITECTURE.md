# NixOS Configuration Architecture Diagrams

## System Overview

```mermaid
graph TB
    subgraph "Single Configuration Source"
        CONFIG[configuration.nix<br/>Main Config]
        HOME[home-vpittamp.nix<br/>Home Manager]
        OVERLAY[overlays/packages.nix<br/>Package Groups]
    end
    
    subgraph "Environment Variables"
        ENV1[NIXOS_CONTAINER]
        ENV2[NIXOS_PACKAGES]
    end
    
    subgraph "Build Targets"
        WSL[NixOS WSL2<br/>Full System]
        CONTAINER[Docker Container<br/>276MB-1GB]
        DEVCONTAINER[VS Code Devcontainer<br/>Development]
    end
    
    CONFIG --> |"isContainer check"| ENV1
    OVERLAY --> |"package selection"| ENV2
    HOME --> CONFIG
    
    ENV1 --> |"empty"| WSL
    ENV1 --> |"=1"| CONTAINER
    ENV1 --> |"=1"| DEVCONTAINER
    
    ENV2 --> |"essential"| CONTAINER
    ENV2 --> |"full"| CONTAINER
    ENV2 --> |"development"| DEVCONTAINER
```

## Package Selection Flow

```mermaid
flowchart LR
    subgraph "Package Groups"
        E[Essential<br/>275MB]
        K[Kubernetes<br/>+325MB]
        D[Development<br/>+325MB]
        X[Extras<br/>+200MB]
    end
    
    subgraph "Profiles"
        P1[essential]
        P2[essential,kubernetes]
        P3[essential,development]
        P4[full]
    end
    
    P1 --> E
    P2 --> E & K
    P3 --> E & D
    P4 --> E & K & D & X
    
    subgraph "Container Sizes"
        S1[275MB]
        S2[600MB]
        S3[600MB]
        S4[1GB]
    end
    
    P1 --> S1
    P2 --> S2
    P3 --> S3
    P4 --> S4
```

## Build Process

```mermaid
sequenceDiagram
    participant User
    participant EnvVars as Environment Variables
    participant Nix as Nix Build
    participant Config as configuration.nix
    participant Overlay as Package Overlay
    participant Output as Build Output
    
    User->>EnvVars: Set NIXOS_CONTAINER=1
    User->>EnvVars: Set NIXOS_PACKAGES="profile"
    User->>Nix: nix build .#container
    
    Nix->>Config: Load configuration
    Config->>Config: Check isContainer
    Config->>EnvVars: Read NIXOS_CONTAINER
    
    alt Container Mode
        Config->>Config: Disable WSL features
        Config->>Config: Enable boot.isContainer
    else WSL Mode
        Config->>Config: Enable WSL features
        Config->>Config: Configure Docker Desktop
    end
    
    Config->>Overlay: Request packages
    Overlay->>EnvVars: Read NIXOS_PACKAGES
    Overlay->>Overlay: Select package groups
    Overlay->>Config: Return package list
    
    Nix->>Output: Build Docker image
    Output->>User: container.tar.gz
```

## Configuration Hierarchy

```mermaid
graph TD
    subgraph "Flake Inputs"
        NIXPKGS[nixpkgs]
        WSL_MOD[nixos-wsl]
        HM[home-manager]
        OP[onepassword-shell-plugins]
    end
    
    subgraph "Main Configuration"
        FLAKE[flake.nix]
        MAIN[configuration.nix]
        CONT[container-profile.nix]
    end
    
    subgraph "User Configuration"
        HOME_CONFIG[home-vpittamp.nix]
        PACKAGES[overlays/packages.nix]
        CUSTOM[packages/*.nix]
    end
    
    NIXPKGS --> FLAKE
    WSL_MOD --> FLAKE
    HM --> FLAKE
    OP --> FLAKE
    
    FLAKE --> |"WSL build"| MAIN
    FLAKE --> |"Container build"| MAIN
    MAIN --> |"Override for containers"| CONT
    
    MAIN --> HOME_CONFIG
    HOME_CONFIG --> PACKAGES
    PACKAGES --> CUSTOM
```

## File Structure

```mermaid
graph TD
    ROOT[/etc/nixos/]
    
    ROOT --> CONFIG[configuration.nix<br/>Main WSL configuration]
    ROOT --> CONTAINER[container-profile.nix<br/>Container overrides]
    ROOT --> HOME[home-vpittamp.nix<br/>User environment]
    ROOT --> FLAKE[flake.nix<br/>Build definitions]
    ROOT --> LOCK[flake.lock<br/>Pinned dependencies]
    ROOT --> BUILD[build-container.sh<br/>Helper script]
    
    ROOT --> OVERLAYS[overlays/]
    OVERLAYS --> PKG_OVERLAY[packages.nix<br/>Package groups]
    
    ROOT --> PACKAGES[packages/]
    PACKAGES --> CLAUDE[claude-manager-fetchurl.nix]
    
    ROOT --> SHELLS[shells/]
    SHELLS --> DEFAULT_SH[default.nix]
    SHELLS --> K8S_SH[k8s.nix]
```

## Container Build Modes

```mermaid
flowchart TB
    START[build-container.sh]
    
    START --> MODE{Mode?}
    
    MODE --> |"Standard"| STD[Standard Container]
    MODE --> |"--devcontainer"| DEV[Devcontainer]
    
    STD --> BUILD1[nix build .#container]
    BUILD1 --> TAR[container.tar.gz]
    TAR --> LOAD1[docker load]
    LOAD1 --> RUN1[docker run]
    
    DEV --> BUILD2[nix build .#container]
    BUILD2 --> LOAD2[docker load]
    LOAD2 --> TAG[docker tag nixos-devcontainer]
    TAG --> DEVCONFIG[Create .devcontainer/]
    DEVCONFIG --> VSCODE[Open in VS Code]
```

## Environment Detection Logic

```mermaid
flowchart TD
    START[System Start]
    
    START --> CHECK{NIXOS_CONTAINER set?}
    
    CHECK --> |"No/Empty"| WSL[WSL Mode]
    CHECK --> |"Yes/Non-empty"| CONT[Container Mode]
    
    WSL --> WSL_FEATURES[Enable WSL Features:<br/>- wsl.enable = true<br/>- Docker Desktop<br/>- VS Code workarounds<br/>- Windows integration]
    
    CONT --> CONT_FEATURES[Enable Container Features:<br/>- boot.isContainer = true<br/>- Disable systemd services<br/>- Minimal environment<br/>- No WSL features]
    
    WSL_FEATURES --> PACKAGES{Select Packages}
    CONT_FEATURES --> PACKAGES
    
    PACKAGES --> PKG_CHECK{NIXOS_PACKAGES set?}
    
    PKG_CHECK --> |"Empty"| DEFAULT[Use 'essential' profile]
    PKG_CHECK --> |"Set"| PARSE[Parse package groups]
    
    DEFAULT --> BUILD[Build System]
    PARSE --> BUILD
```

## Package Overlay System

```mermaid
graph LR
    subgraph "Package Definition"
        DEF[overlays/packages.nix]
        DEF --> ESSENTIAL[essential:<br/>tmux, git, vim,<br/>fzf, ripgrep]
        DEF --> KUBE[kubernetes:<br/>kubectl, helm,<br/>k9s, argocd]
        DEF --> DEV[development:<br/>nodejs, deno,<br/>docker-compose]
        DEF --> EXTRA[extras:<br/>btop, ncdu,<br/>yazi, gum]
    end
    
    subgraph "Selection Logic"
        ENV[NIXOS_PACKAGES]
        ENV --> |"essential"| SEL1[essential only]
        ENV --> |"essential,kubernetes"| SEL2[essential + kubernetes]
        ENV --> |"full"| SEL3[all packages]
    end
    
    subgraph "Final Package List"
        SEL1 --> LIST1[~50 packages]
        SEL2 --> LIST2[~56 packages]
        SEL3 --> LIST3[~70 packages]
    end
```

## Usage Workflow

```mermaid
flowchart LR
    subgraph "Development"
        EDIT[Edit Configuration]
        TEST[Test Locally]
        COMMIT[Commit Changes]
    end
    
    subgraph "Build Options"
        WSL_BUILD[nixos-rebuild switch]
        CONT_BUILD[nix build .#container]
        DEV_BUILD[build-container.sh -d]
    end
    
    subgraph "Deployment"
        WSL_SYS[WSL2 System]
        DOCKER[Docker Registry]
        DEVENV[VS Code Devcontainer]
    end
    
    EDIT --> TEST
    TEST --> COMMIT
    
    COMMIT --> WSL_BUILD
    COMMIT --> CONT_BUILD
    COMMIT --> DEV_BUILD
    
    WSL_BUILD --> WSL_SYS
    CONT_BUILD --> DOCKER
    DEV_BUILD --> DEVENV
```

## Benefits Visualization

```mermaid
mindmap
  root((Unified Config))
    Single Source
      No drift
      Version control
      Reproducible
    Flexible
      Environment vars
      Package profiles
      Multiple targets
    Efficient
      Small containers
      Shared base
      Cached builds
    Developer Friendly
      VS Code integration
      Devcontainers
      Helper scripts
    Maintainable
      Declarative
      Modular
      Well-documented
```