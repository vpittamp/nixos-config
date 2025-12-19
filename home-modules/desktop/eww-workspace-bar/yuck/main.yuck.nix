{ workspaceMarkupDefs, workspacePreviewDefs, windowBlocks, isHeadless, isRyzen, ... }:

''
  ${workspaceMarkupDefs}

  ${workspacePreviewDefs}

  (include "./workspace-preview.yuck")
  (include "./workspace-strip.yuck")

  ;; Feature 057: User Story 2 - Preview Overlay Window (T038, T040)
  (defwindow workspace-preview
    :monitor "${if isHeadless then "HEADLESS-1" else if isRyzen then "DP-1" else "eDP-1"}"
    :windowtype "dock"
    :stacking "overlay"
    :focusable false
    :exclusive false
    :geometry (geometry :anchor "center"
                        :x "0px"
                        :y "0px"
                        :width "600px"
                        :height "800px")
    (workspace-preview-card))

  ${windowBlocks}
''
