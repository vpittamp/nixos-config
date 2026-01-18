# Lazydocker - Terminal UI for Docker
# Custom commands for pushing images to Gitea registry in kind cluster
{ config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
    lazydocker
  ];

  # Desktop entries managed by app-registry.nix (Feature 034)

  xdg.configFile."lazydocker/config.yml".text = ''
    customCommands:
      images:
        - name: "Tag for Gitea (:dev)"
          key: "t"
          attach: true
          command: docker tag {{ .Image.Name }}:{{ .Image.Tag }} gitea.cnoe.localtest.me:8443/giteaadmin/{{ .Image.Name }}:dev
          description: "Tag image for Gitea with :dev"

        - name: "Tag for Gitea (:latest)"
          key: "l"
          attach: true
          command: docker tag {{ .Image.Name }}:{{ .Image.Tag }} gitea.cnoe.localtest.me:8443/giteaadmin/{{ .Image.Name }}:latest
          description: "Tag image for Gitea with :latest"

        - name: "Tag for Gitea (keep tag)"
          key: "k"
          attach: true
          command: docker tag {{ .Image.Name }}:{{ .Image.Tag }} gitea.cnoe.localtest.me:8443/giteaadmin/{{ .Image.Name }}:{{ .Image.Tag }}
          description: "Tag image for Gitea keeping original tag"

        - name: "Push (already tagged)"
          key: "P"
          attach: true
          command: docker push {{ .Image.Name }}:{{ .Image.Tag }}
          description: "Push image (use on gitea.cnoe tagged images)"

        - name: "Tag+Push semver to Gitea"
          key: "v"
          attach: true
          shell: true
          command: "echo -n 'Semver (e.g. 1.2.3): ' ; read V ; docker tag {{ .Image.Name }}:{{ .Image.Tag }} gitea.cnoe.localtest.me:8443/giteaadmin/{{ .Image.Name }}:v$V ; docker push gitea.cnoe.localtest.me:8443/giteaadmin/{{ .Image.Name }}:v$V"
          description: "Prompt for version, tag as v{semver}, push to Gitea"

    gui:
      returnImmediately: false
      wrapMainPanel: true
  '';
}
