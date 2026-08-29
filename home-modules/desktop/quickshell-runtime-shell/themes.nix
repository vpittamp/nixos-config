# The palette set for the runtime shell and the apps that follow it.
#
# One attrset per theme. `colors` are the 24 semantic base tokens Theme.qml
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
{
  zinc-dark = {
    label = "Zinc Dark";
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
