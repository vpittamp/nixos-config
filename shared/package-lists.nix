# Shared package categorization and environment detection
# This file provides utilities for selecting appropriate packages
# based on the environment (container, WSL, full system)
{ pkgs, lib, inputs ? { }, ... }:

let
  packageArgs = { inherit pkgs lib inputs; };

  # Environment detection
  isContainer = builtins.getEnv "NIXOS_CONTAINER" != "";
  isWSL = builtins.pathExists /proc/sys/fs/binfmt_misc/WSLInterop;
  packageEnv = builtins.getEnv "NIXOS_PACKAGES";
  
  # Package selection based on environment
  # Options: "minimal", "essential", "development", "full", or comma-separated list
  getPackageLevel = 
    if packageEnv != "" then packageEnv
    else if isContainer then "essential"
    else "full";

in rec {
  # Environment flags
  inherit isContainer isWSL;
  packageLevel = getPackageLevel;
  
  # Helper functions
  shouldInclude = pkg: level:
    if level == "full" then true
    else if level == "minimal" then false
    else if level == "essential" then 
      builtins.elem pkg [ "git" "vim" "tmux" "curl" "jq" ]
    else
      # Check if package is in comma-separated list
      builtins.elem pkg (lib.splitString "," level);
  
  # Package profiles for different environments
  profiles = {
    # Minimal container profile (for restricted environments)
    container-minimal = {
      system = [ ];  # No custom system packages
      user = (import ../user/packages.nix packageArgs).minimal;
    };
    
    # Essential container profile (for development containers)
    container-essential = {
      system = (import ../system/packages.nix packageArgs).essential;
      user = (import ../user/packages.nix packageArgs).essential;
    };
    
    # Full container profile (for unrestricted containers)
    container-full = {
      system = (import ../system/packages.nix packageArgs).all;
      user = (import ../user/packages.nix packageArgs).development;
    };
    
    # WSL profile (full desktop integration)
    wsl = {
      system = (import ../system/packages.nix packageArgs).all;
      user = (import ../user/packages.nix packageArgs).all;
    };
    
    # Development workstation profile
    workstation = {
      system = (import ../system/packages.nix packageArgs).all;
      user = (import ../user/packages.nix packageArgs).all;
    };
  };
  
  # Get appropriate profile based on environment
  getProfile = 
    if isContainer && getPackageLevel == "minimal" then profiles.container-minimal
    else if isContainer && getPackageLevel == "essential" then profiles.container-essential
    else if isContainer then profiles.container-full
    else if isWSL then profiles.wsl
    else profiles.workstation;
}
