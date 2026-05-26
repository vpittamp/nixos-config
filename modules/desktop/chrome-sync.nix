# Chrome sign-in and sync policy
#
# Allows the user to sign into Chrome with a Google account so that bookmarks,
# history, passwords, and other Chrome settings sync across devices.
#
# `SyncTypesListDisabled` is intentionally unset — its absence is what Chrome
# treats as "all sync types allowed", including bookmarks. Setting it to an
# empty list would have the same effect but is noisier.
#
# This module also removes the stale, non-Nix-managed
# /etc/opt/chrome/policies/managed/managed_policies.json that was installed by
# a previous (imperative) integration and pinned `BrowserSignin: 0`, blocking
# sign-in entirely. Its other two keys are already covered by Nix-managed
# files:
#   - ExtensionInstallForcelist (legacy) → superseded by ExtensionSettings in
#     1password-support.json (modules/services/onepassword.nix)
#   - PasswordManagerEnabled: false → identical value in 1password-support.json
{ lib, ... }:
{
  environment.etc."opt/chrome/policies/managed/chrome-sync.json".text =
    builtins.toJSON {
      BrowserSignin = 1;   # 0=disable, 1=allow user sign-in, 2=force
      SyncDisabled = false;
    };

  systemd.tmpfiles.rules = [
    "r /etc/opt/chrome/policies/managed/managed_policies.json - - - - -"
  ];
}
