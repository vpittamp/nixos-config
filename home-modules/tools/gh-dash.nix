{ pkgs, lib, ... }:

# Register the Nix-packaged gh-dash binary as a gh CLI extension and own the
# global DASH configuration. Per-repo `.gh-dash.yml` files can still override
# sections while inheriting these pager/keybinding defaults.

let
  gh-dash = pkgs.callPackage ../../packages/gh-dash.nix { };
in
{
  home.packages = [ gh-dash ];

  xdg.dataFile."gh/extensions/gh-dash/gh-dash".source =
    lib.getExe gh-dash;

  xdg.configFile."gh-dash/config.yml".text = ''
    # yaml-language-server: $schema=https://gh-dash.dev/schema.json
    pager:
      diff: diffnav

    repoPaths:
      PittampalliOrg/*: /home/vpittamp/repos/PittampalliOrg/*/main
      vpittamp/*: /home/vpittamp/repos/vpittamp/*/main

    keybindings:
      universal:
        - key: g
          name: lazygit
          command: cd {{.RepoPath}} && lazygit
      prs:
        - key: T
          name: actions
          command: gh enhance -R {{.RepoName}} {{.PrNumber}}
        - key: D
          name: diffnav
          command: gh pr diff --repo {{.RepoName}} {{.PrNumber}} | diffnav
        - key: C
          name: checks
          command: gh pr checks --repo {{.RepoName}} {{.PrNumber}}

    defaults:
      preview:
        open: false
        width: 50
      prsLimit: 30
      issuesLimit: 30
      view: prs

    prSections:
      - title: Needs My Review
        filters: is:open review-requested:@me
      - title: My PRs
        filters: is:open author:@me
      - title: Involved
        filters: is:open involves:@me -author:@me

    issuesSections:
      - title: Assigned
        filters: is:open assignee:@me
      - title: Created
        filters: is:open author:@me
      - title: Involved
        filters: is:open involves:@me -author:@me
  '';
}
