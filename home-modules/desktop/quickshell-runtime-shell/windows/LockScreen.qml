import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam
import "root:/"

// In-shell session lock (ext-session-lock) with a PAM password prompt, so the
// lock screen is themed like the rest of the shell and cannot drift from it.
// The lock follows shellRoot.sessionLocked; PAM success clears it, which is
// the only way out — hide/toggle over IPC are refused by the surface registry.
// If the compositor refuses the lock (secure never becomes true) the shell
// falls back to swaylock so a lock request is never silently dropped.
//
// Root is a Scope: WlSessionLock's default property is its surface component,
// so the timer and the PAM context must be siblings of the lock, not children.
Scope {
    id: lock
    required property QtObject shellRoot
    required property QtObject runtimeConfig
    required property var colors
    readonly property QtObject root: shellRoot

    property string status: ""
    property bool authenticating: false
    property string pendingPassword: ""
    property int failedAttempts: 0
    readonly property bool locked: sessionLock.locked
    readonly property bool secure: sessionLock.secure

    function submit(password) {
        if (authenticating || !password) {
            return;
        }
        pendingPassword = password;
        authenticating = true;
        status = "Checking…";
        if (!pam.start()) {
            authenticating = false;
            status = "PAM unavailable";
        }
    }

    // The compositor never granted the lock: give up on the native surface
    // and hand the session to swaylock so it still gets locked.
    Timer {
        id: fallbackTimer
        interval: 1500
        repeat: false
        onTriggered: {
            if (sessionLock.locked && !sessionLock.secure) {
                console.warn("lock: compositor did not grant ext-session-lock, falling back to swaylock");
                lock.root.sessionLocked = false;
                lock.root.runDetached(["swaylock", "-f"]);
            }
        }
    }

    PamContext {
        id: pam
        config: lock.runtimeConfig.lockPamService
        user: lock.runtimeConfig.userName

        onPamMessage: {
            if (responseRequired) {
                respond(lock.pendingPassword);
            }
        }

        onCompleted: function (result) {
            lock.authenticating = false;
            lock.pendingPassword = "";
            if (result === PamResult.Success) {
                lock.status = "";
                lock.root.sessionLocked = false;
                return;
            }
            lock.failedAttempts += 1;
            lock.status = result === PamResult.MaxTries ? "Too many attempts" : "Wrong password";
        }

        onError: function (error) {
            lock.authenticating = false;
            lock.pendingPassword = "";
            lock.status = "Authentication error";
            console.warn("lock: pam error", error);
        }
    }

    WlSessionLock {
        id: sessionLock
        locked: lock.root.sessionLocked

        onSecureStateChanged: {
            if (secure) {
                fallbackTimer.stop();
                lock.status = "";
                lock.failedAttempts = 0;
            }
        }

        onLockStateChanged: {
            if (locked) {
                fallbackTimer.restart();
            } else {
                fallbackTimer.stop();
                pam.abort();
                lock.authenticating = false;
                lock.pendingPassword = "";
            }
        }

        WlSessionLockSurface {
            id: surface
            color: lock.colors.bg

            readonly property bool primary: lock.root.screenOutputName(screen) === (lock.root.focusedOutputName() || lock.root.screenOutputName(screen))

            Rectangle {
                anchors.fill: parent
                color: lock.colors.bg

                // Soft radial wash so the lock reads as a surface, not a black hole.
                Rectangle {
                    anchors.centerIn: parent
                    width: Math.max(parent.width, parent.height) * 1.2
                    height: width
                    radius: width / 2
                    color: lock.colors.blueWash
                    opacity: 0.6
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 14
                width: Math.min(420, parent.width - 80)

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: lock.root.clockTime
                    color: lock.colors.text
                    font.pixelSize: 84
                    font.weight: Font.Light
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: lock.root.clockDate
                    color: lock.colors.muted
                    font.pixelSize: 16
                }

                Item { Layout.preferredHeight: 22 }

                Rectangle {
                    Layout.fillWidth: true
                    height: 46
                    radius: 12
                    color: lock.colors.cardGlass
                    border.color: field.activeFocus ? lock.colors.blue : lock.colors.border
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 12
                        spacing: 10

                        Text {
                            text: "󰌾"
                            color: lock.authenticating ? lock.colors.amber : lock.colors.muted
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 18
                        }

                        TextInput {
                            id: field
                            Layout.fillWidth: true
                            echoMode: TextInput.Password
                            passwordCharacter: "•"
                            color: lock.colors.text
                            font.pixelSize: 16
                            focus: surface.primary
                            enabled: !lock.authenticating
                            clip: true
                            onAccepted: {
                                lock.submit(text);
                                text = "";
                            }
                            Keys.onEscapePressed: text = ""

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !field.text.length
                                text: lock.runtimeConfig.userName + " — password"
                                color: lock.colors.subtle
                                font.pixelSize: 15
                            }
                        }
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: lock.status || (lock.failedAttempts > 0 ? lock.failedAttempts + " failed" : " ")
                    color: lock.status === "Checking…" ? lock.colors.muted : lock.colors.red
                    font.pixelSize: 13
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 6
                    text: lock.root.lockAgentSummary()
                    visible: text.length > 0
                    color: lock.colors.subtle
                    font.pixelSize: 12
                }
            }

            Text {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: 22
                text: lock.runtimeConfig.hostName + " · " + lock.root.screenOutputName(screen)
                color: lock.colors.subtle
                font.pixelSize: 11
            }

            // The surface appears with the lock; grab keyboard focus on the
            // focused output so typing works without a click.
            Timer {
                interval: 60
                running: surface.primary && sessionLock.locked
                repeat: false
                onTriggered: field.forceActiveFocus()
            }
        }
    }
}
