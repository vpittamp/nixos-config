{ config, pkgs, lib, ... }:

{
  programs.btop = {
    enable = true;

    settings = {
      # Color theme - see available themes with 'btop --help'
      color_theme = "Default";

      # Theme background - set to false for transparent terminal background
      theme_background = true;

      # Update time in milliseconds (default 2000 = 2 seconds)
      update_ms = 2000;

      # Processes sorting - "pid", "program", "arguments", "threads", "user", "memory", "cpu lazy", "cpu direct"
      proc_sorting = "memory";

      # Reverse sorting order
      proc_reversed = true;

      # Tree view mode for processes
      proc_tree = false;

      # Show process command in full (with arguments)
      proc_per_core = false;

      # Show memory in megabytes
      proc_mem_bytes = true;

      # Show CPU graph for each core
      proc_cpu_graphs = true;

      # Show process GPU usage (if available)
      show_gpu_info = "Auto";

      # Process filtering - show all processes
      proc_filter_kernel = false;

      # Network settings
      net_download = 100;  # Network graph scale in Mbit/s (auto scales)
      net_upload = 100;
      net_auto = true;  # Auto-detect network interface
      net_sync = false;  # Sync network scales

      # Show network graphs
      net_iface = "";  # Empty = auto-detect

      # Show disks
      show_disks = true;
      only_physical = true;  # Only show physical disks

      # Disk filtering
      disks_filter = "";

      # Show IO stats
      show_io_stat = true;
      io_mode = false;

      # CPU settings
      show_uptime = true;
      cpu_graph_upper = "total";  # "total", "user", "system"
      cpu_graph_lower = "total";
      cpu_invert_lower = true;
      cpu_single_graph = false;

      # Show CPU temperatures
      check_temp = true;
      cpu_sensor = "Auto";
      show_coretemp = true;

      # Temperature unit - true for Celsius, false for Fahrenheit
      temp_scale = true;

      # Show battery stats (if laptop)
      show_battery = true;

      # Memory settings
      mem_graphs = true;
      mem_below_net = false;
      show_swap = true;
      swap_disk = true;

      # UI settings
      show_init = true;
      update_check = false;  # Don't check for updates (NixOS handles this)
      log_level = "WARNING";

      # Vim keys for navigation
      vim_keys = false;

      # Rounded corners
      rounded_corners = true;

      # Graph symbol - "braille", "block", "tty"
      graph_symbol = "braille";

      # Graph symbol for memory/network
      graph_symbol_cpu = "default";
      graph_symbol_mem = "default";
      graph_symbol_net = "default";
      graph_symbol_proc = "default";

      # Clock format
      clock_format = "%X";

      # Background update - keep running in background when minimized
      background_update = true;

      # Custom CPU name (empty = auto-detect)
      custom_cpu_name = "";

      # Enable mouse support
      force_tty = false;
      tty_mode = false;

      # Presets (0-9 to switch)
      presets = "cpu:1:default,proc:0:default cpu:0:default,proc:1:default cpu:0:block,net:0:tty";
    };
  };
}
