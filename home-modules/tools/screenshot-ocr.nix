{ config, lib, pkgs, ... }:

{
  # Screenshot and OCR tools
  home.packages = with pkgs; [
    kdePackages.spectacle  # KDE Plasma screenshot tool
    tesseract              # OCR engine for text extraction
  ];
}
