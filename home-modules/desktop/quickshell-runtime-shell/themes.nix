# The palette set for the runtime shell and the apps that follow it.
#
# One attrset per theme. `style` is the chrome: `flat` (opaque cards with
# accent borders instead of frosted zinc), `radiusScale` (0 = square … 1 =
# the shadcn radii), `fontFamily` ("" = system sans; "monospace" resolves
# through fontconfig), `chipStyle` ("chip" = bordered pills, "text" =
# Omarchy's box-less glyph + label widgets that carry state by colour). `colors` are the 24 semantic base tokens Theme.qml
# is generated from — every other token in the shell (status chip fills,
# elevation films, glass, scrims, washes) is derived from these inside
# Theme.qml, parametrised on `dark`, so a theme is exactly this list and
# nothing else. `terminal` is the same theme's terminal palette (Ghostty;
# herdr follows the terminal), written to ~/.config/ghostty/theme.conf by
# `runtime-theme set`.
#
# The shell is restyled live: `runtime-theme set <name>` writes
# ~/.local/state/quickshell-runtime-shell/theme.json, which the shell watches
# and applies as overrides on the generated Theme.qml singleton — no restart.
# The default theme is baked in at build time (programs.quickshell-runtime-
# shell.theme) so a machine with no state file still has a complete palette.
#
# Besides the two hand-written zinc themes below, every Omarchy palette under
# themes/omarchy/*.toml is converted by `fromOmarchy`: their four backgrounds
# become our elevation ladder, their four foregrounds our text ramp, their
# accent our blue family, and the ANSI hues our status hues (yellow→amber,
# cyan→teal, magenta→violet). The terminal palette is theirs verbatim, so
# `runtime-theme set tokyo-night` restyles the shell and the terminal alike.
let
  strip = c: builtins.substring 1 6 c;
  titleCase = name: builtins.concatStringsSep " " (map
    (w: (builtins.substring 0 1 (builtins.replaceStrings [ "a" "b" "c" "d" "e" "f" "g" "h" "i" "j" "k" "l" "m" "n" "o" "p" "q" "r" "s" "t" "u" "v" "w" "x" "y" "z" ] [ "A" "B" "C" "D" "E" "F" "G" "H" "I" "J" "K" "L" "M" "N" "O" "P" "Q" "R" "S" "T" "U" "V" "W" "X" "Y" "Z" ] w)) + builtins.substring 1 (-1) w)
    (builtins.filter builtins.isString (builtins.split "-" name)));
  fromOmarchy = name: t:
    let
      dark = (t.mode or "dark") == "dark";
      darker = t.darker_background or (t.dark_background or t.background);
      darkBg = t.dark_background or t.background;
      lighter = t.lighter_background or t.selection;
      lightFg = t.light_foreground or t.foreground;
      brightFg = t.bright_foreground or lightFg;
      darkFg = t.dark_foreground or t.muted;
      orange = t.orange or t.yellow;
      bright = key: t.${"bright_" + key} or t.${key};
    in
    {
      label = titleCase name;
      description = "Omarchy ${if dark then "dark" else "light"} theme";
      inherit dark;
      # Omarchy's chrome: opaque cards with accent-tinted borders, square
      # corners (Hyprland rounding 0), the system monospace for all shell text.
      style = { flat = true; radiusScale = 0.0; fontFamily = "monospace"; chipStyle = "text"; };
      colors = {
        bg = darker;
        panel = t.background;
        panelAlt = lighter;
        card = lighter;
        cardAlt = t.background;
        border = t.selection;
        borderStrong = t.muted;
        lineSoft = darkBg;
        text = brightFg;
        textDim = t.foreground;
        muted = darkFg;
        subtle = t.muted;
        accent = lightFg;
        accentBg = t.selection;
        blue = t.accent;
        blueBg = t.selection;
        blueMuted = t.blue or t.accent;
        blueWash = darkBg;
        green = t.green;
        red = t.red;
        amber = t.yellow;
        inherit orange;
        teal = t.cyan;
        violet = t.magenta;
      };
      terminal = {
        background = strip t.background;
        foreground = strip t.foreground;
        cursor = strip t.accent;
        selectionBackground = strip t.selection;
        selectionForeground = strip t.foreground;
        palette = map strip [
          t.selection t.red t.green t.yellow t.blue t.magenta t.cyan lightFg
          t.muted (bright "red") (bright "green") (bright "yellow") (bright "blue") (bright "magenta") (bright "cyan") t.foreground
        ];
      };
    };
  omarchyDir = ./themes/omarchy;
  omarchyThemes = builtins.listToAttrs (map
    (file: let name = builtins.substring 0 (builtins.stringLength file - 5) file; in {
      inherit name;
      value = fromOmarchy name (builtins.fromTOML (builtins.readFile (omarchyDir + "/${file}")));
    })
    (builtins.filter (f: builtins.match ".*\\.toml" f != null) (builtins.attrNames (builtins.readDir omarchyDir))));
in
omarchyThemes // {
  zinc-dark = {
    label = "Zinc Dark";
    # shadcn chrome: frosted cards, zinc borders, rounded corners, system sans.
    style = { flat = false; radiusScale = 1.0; fontFamily = ""; chipStyle = "chip"; };
    description = "shadcn zinc on near-black, Tailwind 400 status hues, Catppuccin Mocha terminal";
    dark = true;
    colors = {
      # base surfaces: bg → card is the elevation ladder
      bg = "#09090b";           # zinc-950
      panel = "#0c0c0f";
      panelAlt = "#121216";
      card = "#18181b";         # zinc-900
      cardAlt = "#131316";
      # lines
      border = "#27272a";       # zinc-800
      borderStrong = "#3f3f46"; # zinc-700
      lineSoft = "#1c1c20";
      # foreground
      text = "#fafafa";         # zinc-50
      textDim = "#d4d4d8";      # zinc-300
      muted = "#a1a1aa";        # zinc-400
      subtle = "#71717a";       # zinc-500
      # accent: near-white on dark, so the status hues mean something
      accent = "#e4e4e7";       # zinc-200
      accentBg = "#1c1c20";
      # the blue family is the interactive accent
      blue = "#60a5fa";
      blueBg = "#111a2e";
      blueMuted = "#3b5f8f";
      blueWash = "#101725";
      # status
      green = "#4ade80";
      red = "#f87171";
      amber = "#fbbf24";
      orange = "#fb923c";
      teal = "#2dd4bf";
      violet = "#a78bfa";
    };
    terminal = {
      # Catppuccin Mocha — what Ghostty already used for bg/fg; the palette
      # makes the ANSI colours explicit instead of Ghostty's defaults.
      background = "1e1e2e";
      foreground = "cdd6f4";
      cursor = "f5e0dc";
      selectionBackground = "585b70";
      selectionForeground = "cdd6f4";
      palette = [
        "45475a" "f38ba8" "a6e3a1" "f9e2af" "89b4fa" "f5c2e7" "94e2d5" "bac2de"
        "585b70" "f38ba8" "a6e3a1" "f9e2af" "89b4fa" "f5c2e7" "94e2d5" "a6adc8"
      ];
    };
  };

  zinc-light = {
    label = "Zinc Light";
    # shadcn chrome: frosted cards, zinc borders, rounded corners, system sans.
    style = { flat = false; radiusScale = 1.0; fontFamily = ""; chipStyle = "chip"; };
    description = "shadcn zinc on white, Tailwind 600 status hues, Catppuccin Latte terminal";
    dark = false;
    colors = {
      bg = "#fafafa";           # zinc-50
      panel = "#f4f4f5";        # zinc-100
      panelAlt = "#ececef";
      card = "#ffffff";
      cardAlt = "#f4f4f5";
      border = "#e4e4e7";       # zinc-200
      borderStrong = "#d4d4d8"; # zinc-300
      lineSoft = "#efeff1";
      text = "#09090b";         # zinc-950
      textDim = "#27272a";      # zinc-800
      muted = "#52525b";        # zinc-600
      subtle = "#71717a";       # zinc-500
      accent = "#18181b";       # zinc-900
      accentBg = "#e4e4e7";
      blue = "#2563eb";         # blue-600
      blueBg = "#dbeafe";       # blue-100
      blueMuted = "#93c5fd";    # blue-300
      blueWash = "#eff6ff";     # blue-50
      green = "#16a34a";
      red = "#dc2626";
      amber = "#d97706";
      orange = "#ea580c";
      teal = "#0d9488";
      violet = "#7c3aed";
    };
    terminal = {
      # Catppuccin Latte
      background = "eff1f5";
      foreground = "4c4f69";
      cursor = "dc8a78";
      selectionBackground = "acb0be";
      selectionForeground = "4c4f69";
      palette = [
        "5c5f77" "d20f39" "40a02b" "df8e1d" "1e66f5" "ea76cb" "179299" "acb0be"
        "6c6f85" "d20f39" "40a02b" "df8e1d" "1e66f5" "ea76cb" "179299" "bcc0cc"
      ];
    };
  };
}
