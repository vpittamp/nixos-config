{ config, pkgs, lib, ... }:

{
  # FZF
  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
    defaultOptions = [
      "--height 40%"
      "--layout=reverse"
      "--border"
      "--inline-info"
      "--color=bg+:${config.colorScheme.surface0},bg:${config.colorScheme.base},spinner:${config.colorScheme.rosewater},hl:${config.colorScheme.red}"
      "--color=fg:${config.colorScheme.text},header:${config.colorScheme.red},info:${config.colorScheme.mauve},pointer:${config.colorScheme.rosewater}"
      "--color=marker:${config.colorScheme.rosewater},fg+:${config.colorScheme.text},prompt:${config.colorScheme.mauve},hl+:${config.colorScheme.red}"
    ];
  };
}