import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import ".." as RootComponents
import "root:/"

// Always-on-top AI-agents monitor strip. Designed to sit on the side of a
// fullscreen app (e.g. the YouTube / YouTube TV PWA) so agent progress can be
// watched WHILE the video plays. On the Overlay layer (renders above fullscreen
// windows), narrow, and exclusiveZone 0 so it reserves no space and leaves the
// rest of the screen — including the video — clickable.
//
// The strip is mouse-interactive (click a row to jump to that session, wheel to
// scroll), but it must not take keyboard focus from the terminal/video surface
// underneath. Pointer-only focus keeps Herdr selection and key routing stable.
PanelWindow {
    required property QtObject shellRoot
    required property QtObject runtimeConfig
    required property var colors
    readonly property QtObject root: shellRoot
    id: monitorWindow

    // Keep the ListView model keyed by stable session identity. The row content
    // still resolves live dashboard data by key, but status/focus ticks no longer
    // reset delegates under the pointer and drop click releases.
    readonly property int dashboardGeneration: root.dashboardGeneration(root.dashboard)
    property var sessionEntries: []
    property bool monitorReady: false

    function clampListContentY(list, value) {
        if (!list) {
            return;
        }
        const maxY = Math.max(0, Number(list.contentHeight || 0) - Number(list.height || 0));
        list.contentY = Math.max(0, Math.min(Number(value || 0), maxY));
    }

    function restoreAgentListContentY(value) {
        if (!monitorWindow.monitorReady) {
            return;
        }
        clampListContentY(agentList, value);
        Qt.callLater(function() {
            clampListContentY(agentList, value);
        });
    }

    function buildSessionEntries() {
        const sessions = root.panelSessions();
        const entries = [];
        for (let i = 0; i < sessions.length; i += 1) {
            const session = sessions[i];
            const key = root.sessionIdentityKey(session);
            if (!key) {
                continue;
            }
            entries.push({
                "identity_key": key,
                "session_key": root.stringOrEmpty(session && session.session_key),
                "snapshot": session,
            });
        }
        return entries;
    }

    function sameSessionEntries(left, right) {
        const a = root.arrayOrEmpty(left);
        const b = root.arrayOrEmpty(right);
        if (a.length !== b.length) {
            return false;
        }
        for (let i = 0; i < a.length; i += 1) {
            if (root.stringOrEmpty(a[i] && a[i].identity_key) !== root.stringOrEmpty(b[i] && b[i].identity_key)) {
                return false;
            }
        }
        return true;
    }

    function refreshSessionEntries(preserveViewport) {
        const savedContentY = preserveViewport && monitorWindow.monitorReady ? Number(agentList.contentY || 0) : 0;
        const next = buildSessionEntries();
        let membershipChanged = false;
        if (!sameSessionEntries(sessionEntries, next)) {
            sessionEntries = next;
            membershipChanged = true;
        }
        // Only a membership change can reset the viewport; restoring on every
        // status tick would fight the user mid-scroll.
        if (preserveViewport && monitorWindow.monitorReady && membershipChanged
            && !agentList.dragging && !agentList.flicking) {
            Qt.callLater(function() {
                monitorWindow.restoreAgentListContentY(savedContentY);
            });
        }
    }

    function liveSessionForEntry(entry, _generation) {
        const sessionKey = root.stringOrEmpty(entry && entry.session_key);
        if (sessionKey) {
            const session = root.sessionByKey(sessionKey);
            if (session) {
                return session;
            }
        }

        const identityKey = root.stringOrEmpty(entry && entry.identity_key);
        const sessions = root.panelSessions();
        for (let i = 0; i < sessions.length; i += 1) {
            const session = sessions[i];
            if (root.sessionIdentityKey(session) === identityKey) {
                return session;
            }
        }

        return entry && entry.snapshot ? entry.snapshot : null;
    }

    Component.onCompleted: {
        monitorReady = true;
        refreshSessionEntries(false);
    }

    onVisibleChanged: {
        if (visible) {
            refreshSessionEntries(false);
        }
    }

    Connections {
        target: root
        // A hidden monitor does not need per-event refreshes; onVisibleChanged
        // rebuilds the entries when it opens.
        enabled: monitorWindow.visible

        function onDashboardChanged() {
            monitorWindow.refreshSessionEntries(true);
        }
    }

    screen: root.findScreenByOutputName(root.agentMonitorOutputName) || root.activeScreen
    visible: root.agentMonitorVisible
    color: "transparent"
    anchors.top: true
    anchors.bottom: true
    anchors.right: true
    implicitWidth: 360
    exclusiveZone: 0
    focusable: false
    aboveWindows: true
    WlrLayershell.namespace: "i3pm-agent-monitor"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
        id: monitorCard
        // MultiEffect is shader-based; the software Quick backend (NVIDIA
        // hosts) would render a layered item as nothing at all, so the shadow
        // is gated and those hosts get the 1px dark halo below instead.
        readonly property bool shadowCapable: GraphicsInfo.api !== GraphicsInfo.Software
        anchors.fill: parent
        anchors.margins: 8
        radius: root.radiusFloat
        // Dark glass: agent text stays readable while the video shows faintly
        // through the strip (idle SessionRows are transparent). The vertical
        // gradient (#131d2a → #0d1117 at glass alpha) adds the elevation cue.
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Theme.cardGlass
            }
            GradientStop {
                position: 1.0
                color: Theme.panelGlass
            }
        }
        border.color: colors.borderStrong
        border.width: 1
        layer.enabled: shadowCapable
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: 1.0
            shadowColor: Theme.shadow
            shadowVerticalOffset: 6
            shadowHorizontalOffset: 0
        }

        Rectangle {
            visible: !monitorCard.shadowCapable
            anchors.fill: parent
            anchors.margins: -1
            radius: parent.radius + 1
            color: "transparent"
            border.color: Theme.edgeShadow
            border.width: 1
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.color: Theme.edgeHighlightSoft
            border.width: 1
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "AI Agents"
                    color: colors.text
                    font.pixelSize: root.fontTitle
                    font.weight: Font.DemiBold
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: monitorWindow.sessionEntries.length
                    color: colors.muted
                    font.pixelSize: root.fontBody
                    font.weight: Font.DemiBold
                }
                Rectangle {
                    width: 22
                    height: 22
                    radius: 11
                    color: closeMouse.containsMouse ? colors.cardAlt : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: colors.muted
                        font.pixelSize: root.fontBody
                    }
                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeAgentMonitor()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: colors.lineSoft
            }

            ScriptModel {
                id: agentSessionsModel
                values: monitorWindow.sessionEntries
                objectProp: "modelData"
            }

            ListView {
                id: agentList
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: monitorWindow.sessionEntries.length > 0
                clip: true
                spacing: 4
                model: agentSessionsModel
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 1200

                // The model is keyed by stable identity, so these fire on
                // membership change only — not on status/focus ticks.
                add: Transition {
                    // Scale, not opacity: SessionRow binds opacity (idle rows
                    // sit at 0.76), and an animation would hold it at 1 until
                    // the next tick re-evaluated the binding.
                    NumberAnimation {
                        property: "scale"
                        from: 0.96
                        to: 1
                        duration: 220
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        property: "x"
                        from: 16
                        to: 0
                        duration: 220
                        easing.type: Easing.OutCubic
                    }
                }
                displaced: Transition {
                    NumberAnimation {
                        property: "y"
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    policy: agentList.contentHeight > agentList.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                }

                delegate: RootComponents.SessionRow {
                    required property var modelData
                    readonly property var liveSession: monitorWindow.liveSessionForEntry(modelData, monitorWindow.dashboardGeneration)
                    width: agentList.width
                    rootObject: root
                    colorsObject: colors
                    surfaceVisible: root.agentMonitorVisible
                    session: liveSession
                    selected: false
                    currentOverrideSet: true
                    currentOverride: root.sessionCurrentOverride(liveSession)
                    interactive: true
                    compact: true
                    showHostToken: true
                    hostColor: root.hostColorFor(root.sessionHostKey(liveSession))
                    showCurrentChip: false
                    closePending: root.sessionClosePending(liveSession)
                    onClicked: root.focusSession(liveSession)
                    onCloseRequested: root.closeSession(liveSession)
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: monitorWindow.sessionEntries.length === 0

                Text {
                    anchors.centerIn: parent
                    text: "No active agents"
                    color: colors.subtle
                    font.pixelSize: root.fontBody
                }
            }
        }
    }
}
