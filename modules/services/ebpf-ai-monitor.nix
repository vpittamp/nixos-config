{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.ebpf-ai-monitor;

  # Use the kernel packages from the current system
  kernelPackages = config.boot.kernelPackages;

  # Python environment with required packages
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    pydantic
  ]);

  # Path to the ebpf_ai_monitor Python module
  # This references the source in home-modules/tools (uses underscore for Python compatibility)
  # Using "${...}" forces Nix to copy the path to the store fresh
  # Version: 5 - fixed BPF event parsing with ctypes.cast
  ebpfAiMonitorSrc = "${../../home-modules/tools}";

in
{
  options.services.ebpf-ai-monitor = {
    enable = mkEnableOption "eBPF-based AI agent process monitor";

    user = mkOption {
      type = types.str;
      description = "Username to monitor AI processes for";
      example = "vpittamp";
    };

    processes = mkOption {
      type = types.listOf types.str;
      default = [ "claude" "codex" ];
      description = "List of process names to monitor for AI agent activity";
      example = [ "claude" "codex" "aider" ];
    };

    waitThreshold = mkOption {
      type = types.int;
      default = 1000;
      description = "Milliseconds before considering a process as waiting for input";
      example = 2000;
    };

    logLevel = mkOption {
      type = types.enum [ "DEBUG" "INFO" "WARNING" "ERROR" "CRITICAL" ];
      default = "INFO";
      description = "Logging verbosity level";
    };
  };

  config = mkIf cfg.enable {
    # Enable BCC for eBPF support
    programs.bcc.enable = true;

    # System packages needed for eBPF monitoring
    environment.systemPackages = with pkgs; [
      bpftrace
      bcc
      libnotify  # For notify-send
    ];

    # Systemd service for the eBPF monitor (runs as root)
    systemd.services.ebpf-ai-monitor = {
      description = "eBPF AI Agent Monitor";
      documentation = [ "https://github.com/vpittamp/nixos-config" ];
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "graphical-session.target" ];

      # Set environment for Python and BCC
      environment = {
        # User to monitor (for Sway socket lookup)
        EBPF_MONITOR_USER = cfg.user;

        PYTHONPATH = lib.concatStringsSep ":" [
          "${ebpfAiMonitorSrc}"
          "${pkgs.bcc}/lib/python${pkgs.python3.pythonVersion}/site-packages"
        ];
        # BCC needs kernel headers to compile eBPF programs
        BCC_KERNEL_SOURCE = "${kernelPackages.kernel.dev}/lib/modules/${kernelPackages.kernel.modDirVersion}/source";
        # Clang include paths for kernel headers (source/include has linux/types.h etc)
        # Order matters: generated/uapi paths first for generated headers like version.h
        CPATH = lib.concatStringsSep ":" [
          # Generated headers (version.h, types.h, etc) - must come first
          "${kernelPackages.kernel.dev}/lib/modules/${kernelPackages.kernel.modDirVersion}/build/include/generated/uapi"
          "${kernelPackages.kernel.dev}/lib/modules/${kernelPackages.kernel.modDirVersion}/build/include/generated"
          "${kernelPackages.kernel.dev}/lib/modules/${kernelPackages.kernel.modDirVersion}/build/arch/x86/include/generated/uapi"
          "${kernelPackages.kernel.dev}/lib/modules/${kernelPackages.kernel.modDirVersion}/build/arch/x86/include/generated"
          # Build headers
          "${kernelPackages.kernel.dev}/lib/modules/${kernelPackages.kernel.modDirVersion}/build/include"
          "${kernelPackages.kernel.dev}/lib/modules/${kernelPackages.kernel.modDirVersion}/build/arch/x86/include"
          # Source headers
          "${kernelPackages.kernel.dev}/lib/modules/${kernelPackages.kernel.modDirVersion}/source/include"
          "${kernelPackages.kernel.dev}/lib/modules/${kernelPackages.kernel.modDirVersion}/source/include/uapi"
          "${kernelPackages.kernel.dev}/lib/modules/${kernelPackages.kernel.modDirVersion}/source/arch/x86/include"
          "${kernelPackages.kernel.dev}/lib/modules/${kernelPackages.kernel.modDirVersion}/source/arch/x86/include/uapi"
        ];
      };

      serviceConfig = {
        Type = "simple";
        # Set working directory to kernel source so BCC's relative includes work
        WorkingDirectory = "${kernelPackages.kernel.dev}/lib/modules/${kernelPackages.kernel.modDirVersion}/source";
        ExecStart = concatStringsSep " " [
          "${pythonEnv}/bin/python3"
          "-m"
          "ebpf_ai_monitor"
          "--user"
          cfg.user
          "--threshold"
          (toString cfg.waitThreshold)
          "--log-level"
          cfg.logLevel
          "--processes"
        ] + " " + (concatStringsSep " " cfg.processes);

        # Run as root (required for eBPF)
        User = "root";
        Group = "root";

        # Restart policy
        Restart = "on-failure";
        RestartSec = 2;

        # Security hardening (minimal due to eBPF and badge file requirements)
        # eBPF needs broad system access, and we write badge files to /run/user
        NoNewPrivileges = false;  # Needed for BPF
        PrivateTmp = false;       # Need access to real /tmp
        ProtectHome = false;      # Need to read process environs
      };

      # Ensure required tools are in PATH
      path = with pkgs; [
        pythonEnv
        bcc
        libnotify
        sudo
        procps  # For ps, pgrep
        coreutils
        kmod    # For modprobe (required by BCC)
        gnumake # For kernel header processing
        clang   # BCC uses clang for eBPF compilation
        gnutar  # BCC calls tar internally
        gzip    # For extracting headers
        xz      # For tar xz decompression
        bash    # For shell commands
        elfutils # For eBPF debugging
        gnugrep # BCC may call grep
        tmux    # For querying tmux sessions
        sway    # For swaymsg to query Sway tree
      ];
    };
  };
}
