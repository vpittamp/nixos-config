{ config, lib, pkgs, ... }:

{
  # k9s: Catppuccin Mocha theme with embedded colors
  xdg.configFile."k9s/skins/catppuccin-mocha.yaml".text = ''
    k9s:
      body:
        fgColor: "#cdd6f4"
        bgColor: "default"
        logoColor: "#89b4fa"

      frame:
        border:
          fgColor: "#45475a"
          focusColor: "#cba6f7"
        title:
          fgColor: "#b4befe"
          bgColor: "default"
          highlightColor: "#fab387"
          counterColor: "#89dceb"
          filterColor: "#cba6f7"
        crumbs:
          fgColor: "#a6adc8"
          bgColor: "#313244"
          activeColor: "#fab387"

      views:
        table:
          fgColor: "#cdd6f4"
          bgColor: "default"
          cursorFgColor: "#11111b"   # dark text on bright selection for readability
          cursorBgColor: "#89b4fa"    # selection background (Catppuccin blue)
          header:
            fgColor: "#b4befe"
            bgColor: "default"
            sorterColor: "#f9e2af"

        logs:
          fgColor: "#bac2de"
          bgColor: "default"
          indicator:
            fgColor: "#11111b"
            bgColor: "#f9e2af"
          # Current-line readability in log view
          cursorFgColor: "#11111b"
          cursorBgColor: "#89b4fa"
  '';

  # Set the skin as default for k9s
  xdg.configFile."k9s/config.yml".text = ''
    k9s:
      skin: catppuccin-mocha
  '';

  # K9s views for External Secrets Operator resources
  xdg.configFile."k9s/views.yml".text = ''
    k9s:
      views:
        # ExternalSecret - individual secrets being synced from external providers
        external-secrets.io/v1beta1/externalsecrets:
          columns:
            - NAME
            - STORE<:.spec.secretStoreRef.name>
            - STORE_KIND<:.spec.secretStoreRef.kind>
            - REFRESH<:.spec.refreshInterval>
            - STATUS<:.status.conditions[0].reason>
            - READY<:.status.conditions[0].status>
            - AGE

        # SecretStore - namespaced configuration for external API access
        external-secrets.io/v1beta1/secretstores:
          columns:
            - NAME
            - PROVIDER<:.spec.provider|keys|[0]>
            - READY<:.status.conditions[0].status>
            - STATUS<:.status.conditions[0].reason>
            - AGE

        # ClusterSecretStore - cluster-wide provider configurations
        external-secrets.io/v1beta1/clustersecretstores:
          columns:
            - NAME
            - PROVIDER<:.spec.provider|keys|[0]>
            - READY<:.status.conditions[0].status>
            - STATUS<:.status.conditions[0].reason>
            - AGE

        # ClusterExternalSecret - cluster-scoped external secrets
        external-secrets.io/v1beta1/clusterexternalsecrets:
          columns:
            - NAME
            - STORE<:.spec.externalSecretSpec.secretStoreRef.name>
            - REFRESH<:.spec.externalSecretSpec.refreshInterval>
            - READY<:.status.conditions[0].status>
            - STATUS<:.status.conditions[0].reason>
            - AGE

        # PushSecret - secrets pushed to external providers
        external-secrets.io/v1alpha1/pushsecrets:
          columns:
            - NAME
            - STORE<:.spec.secretStoreRefs[0].name>
            - STATUS<:.status.conditions[0].reason>
            - READY<:.status.conditions[0].status>
            - AGE
  '';
}