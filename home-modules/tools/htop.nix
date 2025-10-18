{ config, pkgs, lib, ... }:

{
  programs.htop = {
    enable = true;

    settings = {
      # Hide long NixOS paths - show only program names
      show_program_path = false;

      # Highlight just the base program name (not the full path)
      highlight_base_name = true;

      # Find the actual command name in the full command line
      find_comm_in_cmdline = true;

      # Strip executable path from command line
      strip_exe_from_cmdline = true;

      # Hide kernel threads for cleaner view
      hide_kernel_threads = true;

      # Hide userland threads (set to true for even cleaner view)
      hide_userland_threads = false;

      # Don't show full paths
      show_merged_command = false;

      # Sorting - default to memory usage (high to low)
      sort_key = "PERCENT_MEM";
      sort_direction = -1;  # -1 = descending

      # Visual improvements
      highlight_megabytes = true;
      highlight_threads = true;
      highlight_changes = 50;
      highlight_changes_delay_secs = 5;

      # Tree view settings (toggle with 't' key)
      tree_view = false;
      tree_view_always_by_pid = false;

      # Display settings
      header_margin = true;
      detailed_cpu_time = false;
      cpu_count_from_one = false;
      show_cpu_usage = true;
      show_cpu_frequency = false;
      show_cpu_temperature = false;

      # Color scheme (0 = default, 1 = monochrome, etc.)
      color_scheme = 0;

      # Enable mouse support
      enable_mouse = true;

      # Update delay in tenths of seconds (15 = 1.5 seconds)
      delay = 15;

      # Hide the function bar at the bottom (F1-F10) - set to 1 to hide
      hide_function_bar = false;

      # Meters configuration
      # Left side: CPU meters, Memory, Swap
      left_meters = [ "LeftCPUs" "Memory" "Swap" ];
      left_meter_modes = [ 1 1 1 ];  # 1 = bar mode

      # Right side: CPU meters, Tasks, Load Average, Uptime
      right_meters = [ "RightCPUs" "Tasks" "LoadAverage" "Uptime" ];
      right_meter_modes = [ 1 2 2 2 ];  # 1 = bar, 2 = text
    };
  };
}
