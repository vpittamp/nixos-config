# Chrome managed bookmarks policy
#
# Generates /etc/opt/chrome/policies/managed/chrome-managed-bookmarks.json from
# shared/pwa-sites.nix so every PWA URL is reachable as a bookmark in any Chrome
# instance using the Default profile (regular browser, plus app-mode windows via
# the bookmark manager Ctrl+Shift+O).
#
# Folder layout: PWAs whose names share a prefix and differ only by an
# environment suffix (Ryzen/Dev/Staging/Prod/Hub/ThinkPad) collapse into a
# single folder named with the shared prefix; folder children are labelled
# with just the env. Services with only one entry render as a top-level
# bookmark using the entry's full name.
#
# Chrome does NOT merge same-key dictionary policies across files (see
# modules/desktop/chrome-claude.nix:9-13). `ManagedBookmarks` is unique to
# this file, so it coexists with the onepassword.nix-managed policy files.
{ lib, ... }:

let
  pwaSitesData = import ../../shared/pwa-sites.nix { inherit lib; };
  pwas = pwaSitesData.pwaSites;

  envSuffixes = [ "Ryzen" "Dev" "Staging" "Prod" "Hub" "ThinkPad" ];

  splitName = name:
    let
      parts = lib.splitString " " name;
      lastWord = lib.last parts;
      initWords = lib.init parts;
      hasEnvSuffix =
        (builtins.length parts >= 2) && (builtins.elem lastWord envSuffixes);
    in
      if hasEnvSuffix
      then { service = lib.concatStringsSep " " initWords; env = lastWord; }
      else { service = name; env = null; };

  withSplit = map (pwa: pwa // { _split = splitName pwa.name; }) pwas;

  groups = lib.foldl' (acc: pwa:
    let key = pwa._split.service;
    in acc // { ${key} = (acc.${key} or []) ++ [ pwa ]; }
  ) {} withSplit;

  toFolderChild = pwa: {
    name = if pwa._split.env != null then pwa._split.env else pwa.name;
    url = pwa.url;
  };

  bookmarkTree = lib.mapAttrsToList (service: items:
    if builtins.length items == 1
    then let pwa = builtins.head items; in { name = pwa.name; url = pwa.url; }
    else { name = service; children = map toFolderChild items; }
  ) groups;

  managedBookmarks =
    [ { toplevel_name = "PWAs"; } ] ++ bookmarkTree;
in
{
  environment.etc."opt/chrome/policies/managed/chrome-managed-bookmarks.json".text =
    builtins.toJSON { ManagedBookmarks = managedBookmarks; };
}
