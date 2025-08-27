{ config, lib, pkgs, ... }:

let
  colors = config.colorScheme; # Catppuccin Mocha palette
in
{
  # k9s: Catppuccin-aligned, high-contrast skin
  xdg.configFile."k9s/skins/catppuccin-mocha.yaml".text = ''
    k9s:
      body:
        fgColor: "${colors.text}"
        bgColor: "default"
        logoColor: "${colors.blue}"

      frame:
        border:
          fgColor: "${colors.surface1}"
          focusColor: "${colors.mauve}"
        title:
          fgColor: "${colors.lavender}"
          bgColor: "default"
          highlightColor: "${colors.peach}"
          counterColor: "${colors.sky}"
          filterColor: "${colors.mauve}"
        crumbs:
          fgColor: "${colors.subtext0}"
          bgColor: "${colors.surface0}"
          activeColor: "${colors.peach}"

      views:
        table:
          fgColor: "${colors.text}"
          bgColor: "default"
          cursorFgColor: "${colors.crust}"   # dark text on bright selection for readability
          cursorBgColor: "${colors.blue}"    # selection background (Catppuccin blue)
          header:
            fgColor: "${colors.lavender}"
            bgColor: "default"
            sorterColor: "${colors.yellow}"

        logs:
          fgColor: "${colors.subtext1}"
          bgColor: "default"
          indicator:
            fgColor: "${colors.crust}"
            bgColor: "${colors.yellow}"
          # Current-line readability in log view
          cursorFgColor: "${colors.crust}"
          cursorBgColor: "${colors.blue}"
  '';

  # Set the skin as default for k9s
  xdg.configFile."k9s/config.yml".text = ''
    k9s:
      skin: catppuccin-mocha
  '';
}
