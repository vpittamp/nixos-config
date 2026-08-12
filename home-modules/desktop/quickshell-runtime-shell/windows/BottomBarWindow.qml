import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.I3
import Quickshell.Wayland
import Quickshell.Widgets
import ".." as RootComponents
import "root:/"

PanelWindow {
    id: bottomBarWindow
    required property QtObject shellRoot
    required property QtObject runtimeConfig
    required property var colors
    readonly property QtObject root: shellRoot
    required property var modelData
    property bool fallbackMode: false
    property string fallbackOutputName: ""
    readonly property var barScreen: fallbackMode ? null : modelData
    readonly property string barOutputName: fallbackMode ? root.stringOrEmpty(fallbackOutputName) : root.screenOutputName(barScreen)
    property var barWorkspaces: []
    property string barWorkspacesFingerprint: ""

    function refreshBarWorkspaces() {
        const next = root.barWorkspacesForOutput(barOutputName);
        // Only reassign when something a delegate renders actually changed —
        // a plain-array Repeater rebuilds every delegate on assignment.
        const fingerprint = JSON.stringify(next.map(function(workspace) {
            const chip = workspace && workspace.agent_chip;
            return [
                Number(workspace && workspace.num || 0),
                root.stringOrEmpty(workspace && workspace.name),
                root.boolOrFalse(workspace && workspace.focused),
                root.boolOrFalse(workspace && workspace.active),
                root.boolOrFalse(workspace && workspace.urgent),
                Number(workspace && workspace.window_count || 0),
                root.arrayOrEmpty(workspace && workspace.icon_sources),
                chip ? [chip.tool_icon, chip.host_key, chip.status_state] : null,
            ];
        }));
        if (fingerprint === barWorkspacesFingerprint) {
            return;
        }
        barWorkspacesFingerprint = fingerprint;
        barWorkspaces = next;
    }

    onBarOutputNameChanged: refreshBarWorkspaces()
    Component.onCompleted: refreshBarWorkspaces()

    Connections {
        target: root

        function onDashboardChanged() {
            refreshBarWorkspaces();
        }
    }

    // The focused highlight rides Quickshell.I3 (see workspaceIsFocused), not
    // the daemon's event chain — so I3 workspace changes must repaint too,
    // otherwise the fast path would be fast but never triggered.
    readonly property var i3Workspaces: I3.workspaces
    onI3WorkspacesChanged: refreshBarWorkspaces()

    screen: barScreen
    visible: runtimeConfig.perMonitorBars
    color: "transparent"
    anchors.left: true
    anchors.right: true
    anchors.bottom: true
    // Taller in touch mode, because the workspace chips are the thing most
    // often mis-tapped and there is nowhere else for them to grow. At the
    // default 38 the chips get 28 logical px once the bar's margins are taken
    // out — 8.4mm on the Verbatim, under the ~9mm a fingertip needs, and the
    // remaining margin sits between the chips and the screen edge, which is
    // exactly where a finger reaching for the bottom of the screen lands.
    implicitHeight: root.touchModeActive
        ? Math.round(runtimeConfig.barHeight * 1.4)
        : runtimeConfig.barHeight
    exclusiveZone: implicitHeight
    focusable: false
    aboveWindows: true
    WlrLayershell.namespace: "i3pm-runtime-bar-" + (barOutputName || "screen")
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
        anchors.fill: parent
        color: colors.bg
        border.color: colors.border
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            // No bottom margin at all in touch mode: the chips must reach the
            // final pixel row.
            //
            // This is measured, not theoretical. Logging real finger taps on
            // the bottom bar caught one at y=1080 on a 1080-tall screen — the
            // very last row — that did not register. Reaching for a bar at the
            // bottom of the screen, a finger lands *on the edge*, and any
            // margin at all is dead space exactly where the aim concentrates.
            // A target flush against a screen edge cannot be overshot, which is
            // the whole reason bottom bars work; a 3px gap throws that away.
            //
            // The top margin goes too: of 27 logged taps, the five that worked
            // were 15-29px above the bottom and every one at the edge failed,
            // but two failures also landed mid-bar — so rather than trust a
            // calibration this hands the chips the entire bar height and leaves
            // no dead band anywhere for a tap to fall into.
            anchors.topMargin: root.touchModeActive ? 0 : 5
            anchors.bottomMargin: root.touchModeActive ? 0 : 5
            spacing: 8

            Rectangle {
                id: launcherButton
                readonly property bool hovered: launcherMouse.containsMouse
                // Fixed width on purpose. This used to size itself to its
                // contents — the herdr repo:branch title, the git chip, and the
                // output name — so every branch switch, git-status change, or
                // chip appearing re-measured it between 198 and 320px and shoved
                // the whole workspace strip sideways. The pills then looked like
                // they had reordered themselves. Pinning the width costs a
                // little whitespace on short labels and keeps every pill at a
                // fixed screen position, which is what makes them clickable from
                // muscle memory. Children elide into whatever room this leaves.
                Layout.preferredWidth: root.bottomBarLauncherWidth
                Layout.fillHeight: true
                radius: root.radiusControl
                color: root.launcherVisible ? colors.blue : (hovered ? colors.card : colors.cardAlt)
                border.color: root.launcherVisible ? colors.blue : (hovered ? colors.borderStrong : colors.border)
                border.width: 1

                Behavior on color { ColorAnimation { duration: root.fastColorMs } }
                Behavior on border.color { ColorAnimation { duration: root.fastColorMs } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Rectangle {
                        width: 26
                        height: 26
                        radius: root.radiusControl - 1
                        color: root.launcherVisible ? colors.bg : (launcherButton.hovered ? colors.blueWash : colors.card)
                        border.color: root.launcherVisible ? colors.bg : (launcherButton.hovered ? colors.blueMuted : colors.border)
                        border.width: 1

                        Grid {
                            anchors.centerIn: parent
                            columns: 2
                            rows: 2
                            spacing: 3

                            Repeater {
                                model: 4

                                delegate: Rectangle {
                                    width: 6
                                    height: 6
                                    radius: 2
                                    color: root.launcherVisible ? colors.blue : (root.currentContextExecutionMode() === "ssh" ? colors.teal : colors.accent)
                                }
                            }
                        }
                    }

                    Text {
                        text: "Launch"
                        color: root.launcherVisible ? colors.bg : colors.text
                        font.pixelSize: root.fontTitle
                        font.weight: Font.DemiBold
                    }

                    Rectangle {
                        width: 1
                        height: 18
                        color: root.launcherVisible ? Theme.scrim : colors.border
                    }

                    Text {
                        id: launcherContextTitle
                        Layout.fillWidth: true
                        text: root.currentContextTitle()
                        color: root.launcherVisible ? colors.bg : colors.textDim
                        font.pixelSize: root.fontTitle
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        id: contextGitChip
                        visible: root.currentContextGitChipVisible()
                        width: contextGitText.implicitWidth + 10
                        height: 16
                        radius: root.radiusBadge
                        color: root.currentContextGitChipBackground()
                        border.color: "transparent"
                        border.width: 0

                        Text {
                            id: contextGitText
                            anchors.centerIn: parent
                            text: root.currentContextGitChipText()
                            color: root.currentContextGitChipForeground()
                            font.pixelSize: root.fontCaption
                            font.weight: Font.DemiBold
                        }
                    }

                    Text {
                        id: contextOutputText
                        text: barOutputName || root.modeLabel((dashboard.active_context || {}).execution_mode)
                        color: root.launcherVisible ? colors.bg : colors.muted
                        font.pixelSize: root.fontLabel
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: launcherMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleLauncher()
                }

                RootComponents.BarTooltip {
                    anchorWindow: bottomBarWindow
                    anchorItem: launcherMouse
                    above: true
                    active: launcherMouse.containsMouse
                    text: root.currentContextGitTooltip().length > 0 ? ("Open launcher (Meta+D)\n" + root.currentContextGitTooltip()) : "Open launcher (Meta+D)"
                    colors: bottomBarWindow.colors
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Flickable {
                    id: workspaceFlick
                    anchors.fill: parent
                    clip: true
                    contentWidth: workspaceRow.implicitWidth
                    contentHeight: workspaceRow.implicitHeight
                    // Only intercept input when there is actually something to
                    // scroll to. A Flickable takes the pointer grab on press to
                    // work out whether the gesture is a flick, and only hands it
                    // back to its children if the finger barely moved — so with
                    // a fingertip's normal jitter a tap on a workspace button is
                    // swallowed as a would-be drag and has to be repeated. When
                    // the buttons already fit, none of that arbitration is
                    // wanted, and turning it off makes the first tap land.
                    interactive: contentWidth > width

                    Row {
                        id: workspaceRow
                        spacing: 6

                        Repeater {
                            model: barWorkspaces

                            delegate: Rectangle {
                                required property var modelData
                                readonly property var workspace: modelData
                                readonly property string workspaceLabelValue: root.workspaceLabel(workspace)
                                readonly property bool workspaceFocused: root.workspaceIsFocused(workspace)
                                readonly property bool workspaceHovered: workspaceMouse.containsMouse
                                readonly property var workspaceIcons: root.arrayOrEmpty(workspace && workspace.icon_sources)
                                readonly property int workspaceCount: Number(workspace && workspace.window_count || 0)
                                width: Math.max(34, workspaceText.implicitWidth + (workspaceIcons.length ? 30 : 0) + (workspaceCount > 1 ? 16 : 0) + 12)
                                // Fill the strip rather than sitting at a fixed
                                // 28 inside it: any height left over is dead
                                // space that silently swallows taps. Width is
                                // already fine (34 logical minimum ≈ 10mm), so
                                // the height is the whole of the problem.
                                height: workspaceFlick.height > 0 ? workspaceFlick.height : 28
                                radius: root.radiusControl
                                color: workspaceFocused ? colors.blue : (workspaceHovered ? colors.card : (root.boolOrFalse(workspace && workspace.active) ? colors.card : colors.cardAlt))
                                border.color: workspaceFocused ? colors.blue : (root.boolOrFalse(workspace && workspace.urgent) ? colors.red : (workspaceHovered ? colors.borderStrong : colors.border))
                                border.width: 1
                                scale: workspaceMouse.pressed ? 0.96 : 1.0

                                Behavior on color { ColorAnimation { duration: root.fastColorMs } }
                                Behavior on border.color { ColorAnimation { duration: root.fastColorMs } }

                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 90
                                        easing.type: Easing.OutQuad
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 5
                                    anchors.rightMargin: 5
                                    spacing: 2

                                    Row {
                                        spacing: -5
                                        visible: workspaceIcons.length > 0

                                        Repeater {
                                            model: workspaceIcons

                                            delegate: Rectangle {
                                                required property var modelData
                                                required property int index
                                                width: 18
                                                height: 18
                                                radius: root.radiusBadge
                                                color: colors.bg
                                                border.color: workspaceFocused ? colors.blue : colors.borderStrong
                                                border.width: 1

                                                IconImage {
                                                    anchors.centerIn: parent
                                                    implicitSize: 14
                                                    source: String(modelData)
                                                    visible: source !== ""
                                                    mipmap: true
                                                }

                                                // Active agent badge: only on the leading
                                                // (focused window) icon, only when the
                                                // daemon says a herdr session is active
                                                // on this workspace. Host-colored ring,
                                                // tool glyph inside.
                                                Rectangle {
                                                    readonly property var agentChip: index === 0 ? (workspace && workspace.agent_chip) : null
                                                    visible: agentChip !== null && agentChip !== undefined
                                                    anchors.right: parent.right
                                                    anchors.top: parent.top
                                                    anchors.rightMargin: -5
                                                    anchors.topMargin: -5
                                                    width: 11
                                                    height: 11
                                                    radius: 6
                                                    color: colors.bg
                                                    border.color: (agentChip && root.stringOrEmpty(agentChip.host_color)) || colors.borderStrong
                                                    border.width: 1.5

                                                    IconImage {
                                                        anchors.centerIn: parent
                                                        implicitSize: 8
                                                        source: agentChip ? root.stringOrEmpty(agentChip.tool_icon) : ""
                                                        visible: source !== ""
                                                        mipmap: true
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        id: workspaceText
                                        text: workspaceLabelValue
                                        color: workspaceFocused ? colors.bg : (workspaceHovered ? colors.text : colors.textDim)
                                        font.pixelSize: root.fontBody
                                        font.weight: workspaceFocused ? Font.DemiBold : Font.Medium
                                    }

                                    Rectangle {
                                        visible: workspaceCount > 1
                                        width: 14
                                        height: 14
                                        radius: root.radiusBadge
                                        color: workspaceFocused ? colors.bg : colors.card
                                        border.color: workspaceFocused ? colors.bg : colors.border
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: String(workspaceCount)
                                            color: workspaceFocused ? colors.blue : colors.muted
                                            font.pixelSize: root.fontCaption
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                }

                                MouseArea {
                                    id: workspaceMouse
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: root.activateWorkspace(workspace)
                                }

                                // Touch path, for when the row does overflow and
                                // the Flickable above has to stay interactive.
                                // A pointer handler takes part in grab
                                // arbitration properly, so it can still claim a
                                // tap the Flickable is only *considering* as a
                                // flick; MouseArea, on the legacy path, just
                                // loses the grab and the tap goes nowhere.
                                // ReleaseWithinBounds keeps a real drag scrolling.
                                //
                                // Scoped to touchscreens so the mouse keeps its
                                // existing press-to-activate feel. Activating
                                // twice would be harmless anyway — switching to
                                // the workspace you are already on is a no-op.
                                TapHandler {
                                    acceptedDevices: PointerDevice.TouchScreen
                                    gesturePolicy: TapHandler.ReleaseWithinBounds
                                    onTapped: root.activateWorkspace(workspace)
                                }
                            }
                        }
                    }
                }
            }

            // Dictation toggle, right-aligned next to the status group. The
            // workspace area (fillWidth, to its left) takes the whole middle, so
            // the button neither overlaps nor squeezes the workspace buttons.
            // (Was an absolute-centered overlay that sat on top of them.)
            Rectangle {
                id: dictateButton
                Layout.preferredWidth: dictateRow.implicitWidth + 24
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignVCenter
                radius: root.radiusControl
                color: root.voxtypeListening() ? colors.redBg
                    : (root.voxtypeClass() === "stopping" ? colors.amberBg
                    : (dictateMouse.containsMouse ? colors.card : colors.cardAlt)
                    )
                border.width: root.voxtypeActive() ? 2 : 1
                border.color: root.voxtypeActive() ? root.voxtypeIconColor()
                    : (dictateMouse.containsMouse ? colors.borderStrong : colors.border)

                Behavior on color { ColorAnimation { duration: root.fastColorMs } }
                Behavior on border.color { ColorAnimation { duration: root.fastColorMs } }

                RowLayout {
                    id: dictateRow
                    anchors.centerIn: parent
                    spacing: 7

                    Text {
                        id: dictateIcon
                        text: root.voxtypeIcon()
                        color: root.voxtypeActive() ? root.voxtypeIconColor() : colors.muted
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 15

                        // Pulse while listening. alwaysRunToEnd leaves opacity at
                        // 1.0 when it stops, so the icon never gets stuck dimmed.
                        SequentialAnimation on opacity {
                            running: root.voxtypeListening()
                            loops: Animation.Infinite
                            alwaysRunToEnd: true
                            NumberAnimation { from: 1.0; to: 0.3; duration: 600 }
                            NumberAnimation { from: 0.3; to: 1.0; duration: 600 }
                        }
                    }

                    Text {
                        text: root.voxtypeClass() === "streaming" ? "Streaming…"
                            : (root.voxtypeClass() === "recording" ? "Recording…"
                                : (root.voxtypeClass() === "stopping" ? "Stopping…"
                                    : (root.voxtypeClass() === "transcribing" ? "Transcribing…" : "Dictate")))
                        color: root.voxtypeActive() ? root.voxtypeIconColor() : colors.text
                        font.pixelSize: root.fontBody
                        font.weight: Font.DemiBold
                    }
                }

                MouseArea {
                    id: dictateMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runDictationAction("toggle")
                }
            }

            Rectangle {
                Layout.preferredWidth: 214
                Layout.fillHeight: true
                radius: root.radiusControl
                color: colors.card
                border.color: colors.border
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 6

                    Text {
                        text: root.currentLayoutLabel()
                        color: colors.muted
                        font.pixelSize: root.fontLabel
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        id: cycleLayoutButton
                        width: 38
                        height: 24
                        radius: root.radiusControl - 1
                        color: cycleLayoutMouse.containsMouse ? colors.card : colors.cardAlt
                        border.color: cycleLayoutMouse.containsMouse ? colors.borderStrong : colors.border
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "Next"
                            color: colors.text
                            font.pixelSize: root.fontCaption
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: cycleLayoutMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.cycleDisplayLayout()
                        }
                    }

                    Text {
                        text: String(root.activeSessions().length) + " AI"
                        color: colors.text
                        font.pixelSize: root.fontBody
                        font.weight: Font.DemiBold
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: root.radiusControl - 1
                        color: root.panelVisible ? (bottomPanelToggleMouse.containsMouse ? colors.blue : colors.blue) : (bottomPanelToggleMouse.containsMouse ? colors.card : colors.cardAlt)
                        border.color: root.panelVisible ? colors.blue : (bottomPanelToggleMouse.containsMouse ? colors.borderStrong : colors.border)
                        border.width: 1
                        scale: bottomPanelToggleMouse.pressed ? 0.96 : 1.0

                        Behavior on color { ColorAnimation { duration: root.fastColorMs } }
                        Behavior on border.color { ColorAnimation { duration: root.fastColorMs } }

                        Behavior on scale {
                            NumberAnimation {
                                duration: 90
                                easing.type: Easing.OutQuad
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: root.panelVisible ? "Hide" : "Open"
                            color: root.panelVisible ? colors.bg : colors.text
                            font.pixelSize: root.fontLabel
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: bottomPanelToggleMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.togglePanelVisibility(barOutputName)
                        }
                    }
                }
            }
        }
    }
}
