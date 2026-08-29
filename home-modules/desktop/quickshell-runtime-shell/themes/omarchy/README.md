# Omarchy palettes

`<name>.toml` are the `themes/<name>/colors.toml` files from
[basecamp/omarchy](https://github.com/basecamp/omarchy) (quattro branch, MIT;
the palettes themselves belong to their upstream projects — Tokyo Night,
Catppuccin, Gruvbox, Nord, Everforest, Kanagawa, Rosé Pine, …). They are
vendored verbatim; `../../themes.nix` maps their 24 keys onto the shell's
tokens with `builtins.fromTOML`, so adding a theme is dropping a file here.
