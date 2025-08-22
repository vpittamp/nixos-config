{ lib, ... }:
{
  # Define colors that can be imported by other modules
  # Using options to define the color scheme
  options.colorScheme = lib.mkOption {
    type = lib.types.attrs;
    default = {}; 
    description = "Color scheme for the configuration";
  };
  
  config.colorScheme = {
    # Modern color palette inspired by Catppuccin Mocha
    
    # Base colors
    base = "#1e1e2e";
    mantle = "#181825";
    crust = "#11111b";
    
    # Surface colors
    surface0 = "#313244";
    surface1 = "#45475a";
    surface2 = "#585b70";
    
    # Text colors
    text = "#cdd6f4";
    subtext1 = "#bac2de";
    subtext0 = "#a6adc8";
    
    # Main colors
    lavender = "#b4befe";
    blue = "#89b4fa";
    sapphire = "#74c7ec";
    sky = "#89dceb";
    teal = "#94e2d5";
    green = "#a6e3a1";
    yellow = "#f9e2af";
    peach = "#fab387";
    maroon = "#eba0ac";
    red = "#f38ba8";
    mauve = "#cba6f7";
    pink = "#f5c2e7";
    flamingo = "#f2cdcd";
    rosewater = "#f5e0dc";
  };
}