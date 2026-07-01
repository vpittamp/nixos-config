import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.I3
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Wayland
import Quickshell.Widgets
import "controllers/DashboardState.js" as DashboardState
import "controllers" as Controllers
import "windows" as Windows

ShellRoot {
    id: root
    readonly property QtObject shellRootRef: root
    signal displayLayoutStateChanged()

    ShellConfig {
        id: shellConfig
    }

    readonly property var launcherField: launcherWindow ? launcherWindow.launcherFieldRef : null
    readonly property var launcherList: launcherWindow ? launcherWindow.launcherListRef : null
    readonly property var sessionPreviewFlick: launcherWindow ? launcherWindow.sessionPreviewFlickRef : null
    readonly property var settingsCommandQueryField: settingsWindow ? settingsWindow.settingsCommandQueryFieldRef : null
    readonly property var settingsCommandsList: settingsWindow ? settingsWindow.settingsCommandsListRef : null
    readonly property var clock: runtimeServices ? runtimeServices.clockRef : null
    readonly property var launcherFocusTimer: runtimeServices ? runtimeServices.launcherFocusTimerRef : null
    readonly property var launcherQueryDebounce: runtimeServices ? runtimeServices.launcherQueryDebounceRef : null
    readonly property var launcherSessionSwitcherOpenTimer: runtimeServices ? runtimeServices.launcherSessionSwitcherOpenTimerRef : null
    readonly property var launcherWindowSwitcherOpenTimer: runtimeServices ? runtimeServices.launcherWindowSwitcherOpenTimerRef : null
    readonly property var windowSwitcherFocusItem: windowSwitcherWindow ? windowSwitcherWindow.focusItemRef : null
    readonly property var exposeFocusTimer: runtimeServices ? runtimeServices.exposeFocusTimerRef : null
    readonly property var exposeOpenTimer: runtimeServices ? runtimeServices.exposeOpenTimerRef : null
    readonly property var exposeRefreshTimer: runtimeServices ? runtimeServices.exposeRefreshTimerRef : null
    readonly property var sessionPreviewDebounce: runtimeServices ? runtimeServices.sessionPreviewDebounceRef : null
    readonly property var settingsFocusTimer: runtimeServices ? runtimeServices.settingsFocusTimerRef : null
    readonly property var settingsCommandQueryDebounce: runtimeServices ? runtimeServices.settingsCommandQueryDebounceRef : null
    readonly property var snippetEditorProcess: runtimeServices ? runtimeServices.snippetEditorProcessRef : null
    readonly property var settingsCommandQueryProcess: runtimeServices ? runtimeServices.settingsCommandQueryProcessRef : null
    readonly property var launcherQueryProcess: runtimeServices ? runtimeServices.launcherQueryProcessRef : null
    readonly property var displayApplyProcess: runtimeServices ? runtimeServices.displayApplyProcessRef : null
    readonly property var displayToggleOutputProcess: runtimeServices ? runtimeServices.displayToggleOutputProcessRef : null
    readonly property var displayScaleProcess: runtimeServices ? runtimeServices.displayScaleProcessRef : null
    readonly property var displayPresetProcess: runtimeServices ? runtimeServices.displayPresetProcessRef : null
    readonly property var brightnessActionProcess: runtimeServices ? runtimeServices.brightnessActionProcessRef : null
    readonly property var lidPolicyApplyProcess: runtimeServices ? runtimeServices.lidPolicyApplyProcessRef : null
    readonly property var lidInhibitActionProcess: runtimeServices ? runtimeServices.lidInhibitActionProcessRef : null
    readonly property var dashboardWatcher: runtimeServices ? runtimeServices.dashboardWatcherRef : null

    property var dashboard: ({
            status: "loading",
            active_context: {},
            active_terminal: {},
            active_ai_sessions: [],
            focus_state: {},
            display_layout: {},
            outputs: [],
            projects: [],
            worktrees: [],
            scratchpad: {},
            state_health: {},
            total_windows: 0
        })
    property var notificationState: ({
            count: 0,
            dnd: false,
            visible: false,
            inhibited: false,
            has_unread: false,
            display_count: "0",
            error: false
        })
    property var notificationFeed: []
    property var notificationRuntimeMap: ({})
    property var notificationLifecycleConnected: ({})
    property bool notificationCenterVisible: false
    property bool notificationDetailVisible: false
    property var notificationDetailItem: null
    property bool notificationDnd: false
    property var networkState: ({
            connected: false,
            kind: "offline",
            label: "Offline",
            signal: null
        })
    property var daemonHealthState: ({
            status: "unknown",
            events: 0,
            windows: 0,
            uptime: 0,
            issues: ""
        })
    // Voxtype dictation state, fed by `voxtype status --follow --format json`.
    property var voxtypeState: ({
            "class": "idle"
        })
    property bool voxtypeStopRequested: false
    // Live mic input level (0-100) of the default source while recording, fed by
    // dictationLevelBin. Drives the dictation overlay's capture meter so you can
    // see the system is actually hearing speech (not just armed).
    property int dictationLevel: 0
    property string lastDashboardInvariantWarning: ""

    property var systemStatsState: ({
            memory_percent: 0,
            memory_used_gb: 0,
            memory_total_gb: 0,
            swap_used_gb: 0,
            swap_total_gb: 0,
            load1: 0,
            load5: 0,
            load15: 0,
            temperature_c: null,
            system_generation: 0,
            disk_percent: 0,
            disk_used_gb: 0,
            disk_total_gb: 0
        })
    property var brightnessState: ({
            display: {
                available: false,
                label: "Display brightness",
                device: "",
                percent: 0,
                current: 0,
                max: 0
            },
            keyboard: {
                available: false,
                label: "Keyboard backlight",
                device: "",
                percent: 0,
                current: 0,
                max: 0
            }
        })
    property var lidPolicyState: ({
            supported: false,
            host: "",
            fragment_path: "",
            battery: "suspend",
            externalPower: "lock",
            docked: "ignore",
            inhibitActive: false,
            inhibitPid: 0
        })
    property bool panelVisible: true
    // Output name of the monitor whose bar button opened the runtime panel.
    // Empty string falls the panel back to the focused monitor (activeScreen),
    // e.g. when opened via keybinding/IPC which carry no monitor context.
    property string panelOutputName: ""
    property string panelSection: "runtime"
    property string runtimePanelExpandedSection: "sessions"
    property bool dockedMode: true
    property bool powerMenuVisible: false
    property bool audioPopupVisible: false
    // PipeWire: bind default sink/source so their properties (ready, audio) become available
    readonly property PwNode pipewireSink: Pipewire.defaultAudioSink
    readonly property PwNode pipewireSource: Pipewire.defaultAudioSource

    PwObjectTracker {
        objects: [root.pipewireSink, root.pipewireSource]
    }

    // Track all PipeWire nodes so sink list in audio popup can access .ready/.audio
    PwObjectTracker {
        objects: Pipewire.nodes ? Pipewire.nodes.values : []
    }
    property bool bluetoothPopupVisible: false
    // Output name of the bar whose chip opened the audio/bluetooth/power popup, so
    // it appears on the monitor where it was clicked (not the configured primary,
    // which may be off). One shared name: these popups are mutually exclusive.
    property string barPopupOutputName: ""
    property bool displaySelectorVisible: false
    property string displaySelectorOutputName: ""
    // Minimalist always-on-top AI-agents monitor strip: lets you watch a
    // fullscreen app (e.g. the TV PWA) while keeping an eye on agent sessions.
    // Overlay layer, no keyboard grab, narrow side strip.
    property bool agentMonitorVisible: false
    property string agentMonitorOutputName: ""
    property bool worktreePickerVisible: false
    property bool launcherVisible: false
    property bool launcherLoading: false
    property bool launcherNormalizingInput: false
    property bool settingsVisible: false
    property string settingsSection: "commands"
    property string settingsCommandQuery: ""
    property bool settingsCommandNormalizingInput: false
    property bool settingsCommandLoading: false
    property string settingsCommandError: ""
    property int settingsCommandSelectedIndex: 0
    property var settingsCommandEntries: []
    property string launcherMode: "apps"
    property string launcherAppFilter: "all"
    property bool launcherSessionSwitcherActive: false
    property int launcherSessionSwitcherPendingDelta: 0
    property bool launcherWindowSwitcherActive: false
    property int launcherWindowSwitcherPendingDelta: 0
    // Full-screen window-switcher exposé state (separate from the launcher).
    property bool exposeVisible: false
    // Timestamp of the last open, used to ignore a stray second swipe right after
    // opening (so the gesture-toggle doesn't open-then-instantly-close).
    property double exposeOpenedAtMs: 0
    readonly property int exposeReopenGuardMs: 300
    // Synthetic panel key for the herdr "AI Agents" section in the exposé.
    readonly property string exposeAgentsOutput: "__agents__"
    property var exposeEntries: []
    property int exposeSelectedIndex: 0
    property bool exposeSwitcherActive: false
    property int exposePendingDelta: 0
    property string exposeQuery: ""
    // Output name of the monitor where the exposé was activated, so the overlay
    // maps on that monitor. Empty falls back to root.activeScreen.
    property string exposeOutputName: ""
    // Client-side MRU recency for windows (the daemon exposes no focus order):
    // each focused-window change stamps an increasing seq, so the exposé can
    // order tiles most-recently-used first within each monitor panel.
    property var exposeRecency: ({})
    property int exposeRecencySeq: 0
    readonly property int exposeCurrentWindowId: Number((dashboardFocusState() || {}).current_window_id || 0)
    onExposeCurrentWindowIdChanged: {
        if (exposeCurrentWindowId > 0) {
            exposeRecency[exposeCurrentWindowId] = ++exposeRecencySeq;
        }
    }
    property string launcherQuery: ""
    property string launcherError: ""
    property int launcherSelectedIndex: 0
    property var launcherEntries: []
    property var launcherSessionEntryOrder: []
    property bool launcherPointerSelectionEnabled: true
    property string launcherSelectionMode: "initial"
    property bool launcherViewportPrimed: false
    property bool snippetEditorBusy: false
    property string snippetEditorError: ""
    property string snippetEditorMessage: ""
    property int snippetEditorIndex: -1
    property int snippetEditorSelectionHint: -1
    property bool snippetEditorNewDraft: false
    property bool snippetEditorDirty: false
    property bool snippetEditorSyncing: false
    property string snippetEditorLoadedIdentity: ""
    property string snippetEditorName: ""
    property string snippetEditorCommand: ""
    property string snippetEditorDescription: ""
    property var onePasswordEntriesCache: []
    property var expandedSessionGroups: ({})
    property var collapsedHerdrSpaceGroups: ({})
    property string lastFocusedSessionKey: ""
    property var localFocusIntent: null
    property var sessionClosePendingMap: ({})
    property string displayApplyTarget: ""
    property string displayApplyStdout: ""
    property string displayApplyStderr: ""
    property string displayApplyError: ""
    property string displayPresetTarget: ""
    property string displayToggleTarget: ""
    property string displayToggleStdout: ""
    property string displayToggleStderr: ""
    property string displayScaleTarget: ""
    property string displayScaleStdout: ""
    property string displayScaleStderr: ""
    property string brightnessActionTarget: ""
    property string brightnessQueuedTarget: ""
    property int brightnessQueuedPercent: -1
    property string brightnessActionStdout: ""
    property string brightnessActionStderr: ""
    property string brightnessActionError: ""
    property string lidPolicyDraftBattery: "suspend"
    property string lidPolicyDraftExternalPower: "lock"
    property string lidPolicyDraftDocked: "ignore"
    property bool lidPolicyDraftDirty: false
    property string lidPolicyApplyStdout: ""
    property string lidPolicyApplyStderr: ""
    property string lidPolicyApplyError: ""
    property string lidInhibitActionStdout: ""
    property string lidInhibitActionStderr: ""
    property string lidInhibitActionError: ""
    property string lidInhibitActionMode: ""
    property string sessionPreviewTargetKey: ""
    property var sessionPreview: ({
            status: "idle",
            kind: "status",
            session_key: "",
            preview_mode: "",
            preview_reason: "",
            is_live: false,
            is_remote: false,
            tool: "",
            project_name: "",
            host_name: "",
            connection_key: "",
            execution_mode: "",
            focus_mode: "",
            availability_state: "",
            focusability_reason: "",
            window_id: 0,
            bridge_state: "",
            pane_label: "",
            pane_title: "",
            surface_key: "",
            agent_status: "",
            cwd: "",
            foreground_cwd: "",
            workspace_id: "",
            tab_id: "",
            pane_id: "",
            terminal_id: "",
            content: "",
            message: "",
            updated_at: ""
        })
    readonly property var primaryScreen: resolvePrimaryScreen()
    readonly property string primaryOutputName: screenOutputName(primaryScreen)
    // Screen the floating side panel and launcher should appear on. Normally the
    // configured primary, but when no configured primary output is currently
    // active (e.g. clamshell mode, where eDP-1 is disabled), follow the focused
    // monitor so they show on the active screen instead of the dead one.
    readonly property var activeScreen: configuredPrimaryActive()
        ? primaryScreen
        : (findScreenByOutputName(focusedOutputName())
            || (arrayOrEmpty(Quickshell.screens)[0] || primaryScreen))
    readonly property bool hasQuickshellScreens: arrayOrEmpty(Quickshell.screens).length > 0
    readonly property bool useFallbackScreenWindows: !hasQuickshellScreens
    readonly property string fallbackOutputName:
        focusedOutputName() || livePrimaryOutputName() || primaryOutputName || "DP-1"
    readonly property var settingsSectionsModel: [
        {
            id: "commands",
            label: "Commands",
            subtitle: "Elephant snippets",
            title: "Commands",
            icon: "insert-text",
            fallbackGlyph: "$",
            accentColorKey: "teal",
            accentBgKey: "tealBg"
        },
        {
            id: "apps",
            label: "Apps",
            subtitle: "Live registry + declarative sync",
            title: "Apps",
            icon: "application-x-executable",
            fallbackGlyph: "A",
            accentColorKey: "orange",
            accentBgKey: "orangeBg"
        },
        {
            id: "displays",
            label: "Displays",
            subtitle: "Layouts, outputs, scale",
            title: "Displays",
            icon: "video-display",
            fallbackGlyph: "▣",
            accentColorKey: "blue",
            accentBgKey: "blueBg"
        },
        {
            id: "devices",
            label: "Devices",
            subtitle: "Audio, brightness, power",
            title: "Devices",
            icon: "preferences-system",
            fallbackGlyph: "◈",
            accentColorKey: "violet",
            accentBgKey: "violetBg"
        }
    ]
    readonly property var launcherModesModel: [
        {
            id: "apps",
            label: "Apps",
            title: "Launch App",
            placeholder: "Search apps, aliases, or use scope:scoped, pwa, ws:3, monitor:primary",
            help: "Tab modes  •  Up/Down results  •  Chips filter  •  Ctrl+2 URLs",
            icon: "application-x-executable",
            fallbackGlyph: "A",
            accentColorKey: "blue",
            accentBgKey: "blueBg"
        },
        {
            id: "snippets",
            label: "Commands",
            title: "Curated Commands",
            placeholder: "Search curated commands",
            help: "Enter run  •  Shift+Enter scratchpad  •  Manage via toggle-runtime-settings",
            icon: "insert-text",
            fallbackGlyph: "$",
            accentColorKey: "teal",
            accentBgKey: "tealBg"
        },
        {
            id: "files",
            label: "Files",
            title: "Find File",
            placeholder: "Search files from home or type a path prefix",
            help: "Enter open  •  Ctrl+Enter location  •  Ctrl+1 Apps",
            icon: "folder",
            fallbackGlyph: "F",
            accentColorKey: "teal",
            accentBgKey: "tealBg"
        },
        {
            id: "urls",
            label: "URLs",
            title: "Open URL",
            placeholder: "Search Chrome URLs, bookmarks, tabs, or paste a link",
            help: "Enter open  •  Shift+Enter browser  •  Ctrl+Enter copy",
            icon: "internet-web-browser",
            fallbackGlyph: "U",
            accentColorKey: "teal",
            accentBgKey: "tealBg"
        },
        {
            id: "runner",
            label: "Runner",
            title: "Run Command",
            placeholder: "Type a shell command",
            help: "Tab modes  •  Enter run  •  Shift+Enter terminal  •  Ctrl+9 Snippets",
            icon: "utilities-terminal",
            fallbackGlyph: ">",
            accentColorKey: "orange",
            accentBgKey: "orangeBg"
        },
        {
            id: "onepassword",
            label: "1Password",
            title: "1Password",
            placeholder: "Search 1Password",
            help: "Enter password  •  Ctrl+Enter OTP  •  Shift+Enter username",
            icon: "dialog-password-symbolic",
            fallbackGlyph: "1P",
            accentColorKey: "accent",
            accentBgKey: "accentBg"
        },
        {
            id: "clipboard",
            label: "Clipboard",
            title: "Clipboard",
            placeholder: "Search clipboard history",
            help: "Tab modes  •  Enter smart paste  •  Ctrl+D remove",
            icon: "edit-paste",
            fallbackGlyph: "C",
            accentColorKey: "amber",
            accentBgKey: "amberBg"
        },
        {
            id: "sessions",
            label: "Herdr",
            title: "Herdr Monitor",
            placeholder: "Filter AI sessions",
            help: "Mod+Tab cycle  •  Release Mod to focus  •  Enter focus",
            iconFile: shellConfig.aiFallbackIcon,
            fallbackGlyph: "AI",
            accentColorKey: "violet",
            accentBgKey: "violetBg"
        }
    ]
    readonly property var launcherAppFiltersModel: [
        {
            id: "all",
            label: "All",
            icon: "view-grid",
            fallbackGlyph: "•"
        },
        {
            id: "scoped",
            label: "Scoped",
            icon: "applications-development",
            fallbackGlyph: "S"
        },
        {
            id: "global",
            label: "Global",
            icon: "globe",
            fallbackGlyph: "G"
        },
        {
            id: "pwa",
            label: "PWA",
            icon: "internet-web-browser",
            fallbackGlyph: "P"
        },
        {
            id: "workspace",
            label: "Pinned WS",
            icon: "view-list-details",
            fallbackGlyph: "WS"
        }
    ]


    readonly property var colors: ({
            bg: "#0d1117",
            panel: "#111827",
            panelAlt: "#131d2a",
            card: "#161f2c",
            cardAlt: "#0f1722",
            border: "#273244",
            borderStrong: "#334155",
            text: "#e7edf5",
            muted: "#92a1b5",
            subtle: "#64748b",
            lineSoft: "#202b3a",
            textDim: "#b4c0d1",
            accent: "#d1fae5",
            accentBg: "#123329",
            green: "#86efac",
            greenBg: "#10281c",
            blue: "#93c5fd",
            blueBg: "#16243a",
            blueMuted: "#5d7ba2",
            blueWash: "#152231",
            amber: "#f7d38c",
            amberBg: "#3a2912",
            orange: "#fb923c",
            orangeBg: "#3a2414",
            red: "#fda4af",
            redBg: "#3b1820",
            teal: "#67e8f9",
            tealBg: "#102a33",
            violet: "#c4b5fd",
            violetBg: "#241b43"
        })
    readonly property int fastColorMs: 90

    Timer {
        id: voxtypeStopIntentTimer
        interval: 8000
        repeat: false
        onTriggered: root.voxtypeStopRequested = false
    }

    onLauncherAppFilterChanged: {
        if (launcherVisible && launcherMode === "apps") {
            launcherQueryDebounce.restart();
        }
    }

    function arrayOrEmpty(value) {
        if (!value) {
            return [];
        }
        if (Array.isArray(value)) {
            return value;
        }
        try {
            return Array.from(value);
        } catch (_error) {
            return [];
        }
    }

    function stringOrEmpty(value) {
        return value === undefined || value === null ? "" : String(value);
    }

    function themeColor(key, fallback) {
        const value = stringOrEmpty(key);
        if (value && colors && colors[value] !== undefined) {
            return colors[value];
        }
        return fallback === undefined ? "transparent" : fallback;
    }

    function iconSource(iconName, iconFile) {
        const themed = stringOrEmpty(iconName);
        if (themed) {
            const resolved = Quickshell.iconPath(themed, true);
            if (resolved) {
                return resolved;
            }
        }

        const fileValue = stringOrEmpty(iconFile);
        if (!fileValue) {
            return "";
        }
        if (fileValue.indexOf("file://") === 0) {
            return fileValue;
        }
        if (fileValue.indexOf("/") === 0) {
            return "file://" + fileValue;
        }
        return fileValue;
    }

    function settingsSectionMeta(section) {
        const target = stringOrEmpty(section).toLowerCase();
        const sections = arrayOrEmpty(settingsSectionsModel);
        for (let index = 0; index < sections.length; index += 1) {
            if (stringOrEmpty(sections[index] && sections[index].id) === target) {
                return sections[index];
            }
        }
        return sections.length ? sections[0] : null;
    }

    function launcherModeMeta(mode) {
        const target = stringOrEmpty(mode).toLowerCase();
        const modes = arrayOrEmpty(launcherModesModel);
        for (let index = 0; index < modes.length; index += 1) {
            if (stringOrEmpty(modes[index] && modes[index].id) === target) {
                return modes[index];
            }
        }
        return modes.length ? modes[0] : null;
    }

    function launcherAppFilterMeta(filterName) {
        const target = stringOrEmpty(filterName).toLowerCase();
        const filters = arrayOrEmpty(launcherAppFiltersModel);
        for (let index = 0; index < filters.length; index += 1) {
            if (stringOrEmpty(filters[index] && filters[index].id) === target) {
                return filters[index];
            }
        }
        return filters.length ? filters[0] : null;
    }

    function shortProject(name) {
        const value = stringOrEmpty(name);
        if (!value || value === "global") {
            return "Global";
        }

        const accountSplit = value.split("/");
        const repo = accountSplit[accountSplit.length - 1] || value;
        return repo;
    }

    function normalizeHostAlias(host) {
        return stringOrEmpty(host).trim().toLowerCase();
    }

    function currentHostAlias() {
        return normalizeHostAlias(shellConfig.hostName);
    }

    function modeLabel(mode) {
        const value = stringOrEmpty(mode).toLowerCase();
        if (value === "ssh") {
            return "SSH";
        }
        if (value === "local") {
            return "Local";
        }
        return value ? value : "Global";
    }

    // The bottom-bar context chip is keyed off the focused Herdr space (the repo
    // you're actually working in) rather than the retired project system. Herdr
    // spaces already carry repo_name / branch_label and the same git_* fields the
    // chip renders, so this is a drop-in source swap.
    function focusedHerdrSpace() {
        const fs = dashboard.focus_state || {};
        // Deterministic: the daemon reports the focused herdr pane via
        // current_session_key (empty when sway focus is not on a herdr window).
        // No focused pane => no current space => the chip reads "Global". This is
        // a pure function of real focus, with no "any focused space" fallback.
        if (!stringOrEmpty(fs.current_session_key)) {
            return null;
        }
        const host = normalizeHostAlias(fs.current_herdr_host);
        const spaces = herdrSpaces();
        for (let i = 0; i < spaces.length; i += 1) {
            const space = spaces[i];
            if (!boolOrFalse(space && space.focused)) {
                continue;
            }
            const spaceHost = normalizeHostAlias(space.host_key || space.host_label);
            if (!host || spaceHost === host) {
                return space;
            }
        }
        return null;
    }

    function currentContextTitle() {
        const space = focusedHerdrSpace();
        if (space) {
            const repo = stringOrEmpty(space.repo_name);
            const branch = stringOrEmpty(space.branch_label);
            if (repo && branch && repo !== branch) {
                return repo + ":" + branch;
            }
            if (repo) {
                return repo;
            }
            const label = stringOrEmpty(space.label);
            if (label) {
                return label;
            }
        }
        return "Global";
    }

    function currentContextExecutionMode() {
        const space = focusedHerdrSpace();
        return space ? stringOrEmpty(space.execution_mode) : "";
    }

    function currentContextGitSource() {
        return focusedHerdrSpace();
    }

    function currentContextGitChipText() {
        const source = currentContextGitSource();
        if (!source) {
            return "";
        }
        const snapshot = source.git_snapshot && typeof source.git_snapshot === "object" ? source.git_snapshot : ({});
        const compact = stringOrEmpty(source.git_status_compact) || stringOrEmpty(source.git_compact) || stringOrEmpty(snapshot.status_compact);
        const freshness = (stringOrEmpty(source.git_freshness) || stringOrEmpty(snapshot.freshness)).toLowerCase();
        if (!compact && freshness !== "stale") {
            return "";
        }
        if (!compact) {
            return "~";
        }
        return freshness === "stale" ? (compact + " ~") : compact;
    }

    function currentContextGitChipVisible() {
        return currentContextGitChipText().length > 0;
    }

    function currentContextGitChipForeground() {
        const source = currentContextGitSource();
        if (!source) {
            return colors.muted;
        }
        const snapshot = source.git_snapshot && typeof source.git_snapshot === "object" ? source.git_snapshot : ({});
        const state = stringOrEmpty(source.git_state || snapshot.state).toLowerCase();
        const dirtyCount = Number(source.dirty_count || snapshot.dirty_count || 0);
        const behind = Number(source.behind || snapshot.behind || 0);
        const ahead = Number(source.ahead || snapshot.ahead || 0);
        if (state === "conflicted" || state === "dirty" || dirtyCount > 0) {
            return colors.red;
        }
        if (behind > 0) {
            return colors.red;
        }
        if (ahead > 0) {
            return colors.green;
        }
        return colors.muted;
    }

    function currentContextGitChipBackground() {
        const source = currentContextGitSource();
        if (!source) {
            return colors.panelAlt;
        }
        const snapshot = source.git_snapshot && typeof source.git_snapshot === "object" ? source.git_snapshot : ({});
        const state = stringOrEmpty(source.git_state || snapshot.state).toLowerCase();
        const dirtyCount = Number(source.dirty_count || snapshot.dirty_count || 0);
        const behind = Number(source.behind || snapshot.behind || 0);
        const ahead = Number(source.ahead || snapshot.ahead || 0);
        if (state === "conflicted" || state === "dirty" || dirtyCount > 0 || behind > 0) {
            return Qt.tint(colors.panelAlt, Qt.rgba(0.99, 0.64, 0.69, 0.08));
        }
        if (ahead > 0) {
            return Qt.tint(colors.panelAlt, Qt.rgba(0.53, 0.94, 0.67, 0.06));
        }
        return Qt.tint(colors.panelAlt, Qt.rgba(0.53, 0.94, 0.67, 0.04));
    }

    function currentContextGitTooltip() {
        const source = currentContextGitSource();
        if (!source) {
            return "";
        }
        const snapshot = source.git_snapshot && typeof source.git_snapshot === "object" ? source.git_snapshot : ({});
        const tooltip = stringOrEmpty(source.git_status_tooltip) || stringOrEmpty(source.git_tooltip) || stringOrEmpty(snapshot.status_tooltip);
        if (tooltip.length > 0) {
            return tooltip;
        }
        const compact = currentContextGitChipText();
        const title = currentContextTitle();
        return compact.length > 0 ? (title + "\nGit: " + compact) : "";
    }

    function activeContextProjectName() {
        const context = dashboard.active_context || {};
        return stringOrEmpty(context.qualified_name || context.project_name);
    }
    function activeContextTargetHost() {
        const context = dashboard.active_context || {};
        return normalizeHostAlias(context.target_host || context.host_alias || shellConfig.hostName);
    }

    function isGlobalContext() {
        const project = activeContextProjectName();
        return !project || project === "global";
    }

    function activeSessions() {
        return arrayOrEmpty(dashboard.active_ai_sessions);
    }

    function sessionMru() {
        return activeSessions();
    }

    function panelSessions() {
        return stableSortedSessions(activeSessions().filter(session => sessionIsPanelDisplayEligible(session)));
    }

    function sessionIdentityKey(session) {
        const sessionKey = stringOrEmpty(session && session.session_key);
        if (sessionKey) {
            return sessionKey;
        }

        const renderSessionKey = stringOrEmpty(session && session.render_session_key);
        if (renderSessionKey) {
            return renderSessionKey;
        }

        const herdrSession = stringOrEmpty(session && session.herdr_session);
        if (herdrSession) {
            return herdrSession;
        }

        const paneId = stringOrEmpty(session && session.pane_id);
        if (paneId) {
            return "herdr:pane:" + paneId;
        }

        const surfaceKey = stringOrEmpty(session && session.surface_key);
        if (surfaceKey) {
            return surfaceKey;
        }

        return [stringOrEmpty(session && session.tool), stringOrEmpty(session && session.connection_key), stringOrEmpty(session && session.context_key), String(Number(session && session.window_id || 0)), String(Number(session && session.pid || 0)), String(Number(session && session.pane_pid || 0)), stringOrEmpty(session && session.pane_label)].join("::");
    }

    function uniqueSessions(items) {
        const list = arrayOrEmpty(items);
        const unique = [];
        const seen = {};

        for (let i = 0; i < list.length; i += 1) {
            const session = list[i];
            const identityKey = sessionIdentityKey(session);
            if (!identityKey || seen[identityKey]) {
                continue;
            }
            seen[identityKey] = true;
            unique.push(session);
        }

        return unique;
    }

    function firstNumber(value, fallback) {
        const match = stringOrEmpty(value).match(/-?\d+/);
        if (!match || !match.length) {
            return fallback;
        }
        const parsed = Number(match[0]);
        return Number.isFinite(parsed) ? parsed : fallback;
    }

    function compareAscending(left, right) {
        if (left < right) {
            return -1;
        }
        if (left > right) {
            return 1;
        }
        return 0;
    }

    function compareDescending(left, right) {
        if (left > right) {
            return -1;
        }
        if (left < right) {
            return 1;
        }
        return 0;
    }

    function sessionWindowSlot(session) {
        return firstNumber(session && (session.tab_id || session.workspace_id), 1000000);
    }

    function sessionPaneSlot(session) {
        return firstNumber(session && session.pane_id, firstNumber(session && session.pane_label, 1000000));
    }

    function sessionIsCurrentHost(session) {
        return boolOrFalse(session && session.is_current_host);
    }

    function windowIdValue(windowData) {
        return Number(windowData && (windowData.id || windowData.window_id) || 0);
    }

    function dashboardFocusState() {
        return dashboard && typeof dashboard.focus_state === "object" ? dashboard.focus_state : {};
    }

    function pendingFocusIntent() {
        const focusState = dashboardFocusState();
        const intent = focusState && typeof focusState.focus_intent === "object" ? focusState.focus_intent : null;
        const pendingIntentId = stringOrEmpty(focusState.pending_intent_id);
        if (intent
                && pendingIntentId
                && pendingIntentId === stringOrEmpty(intent.intent_id)
                && stringOrEmpty(intent.state) === "pending") {
            return intent;
        }
        if (localFocusIntent && stringOrEmpty(localFocusIntent.state) === "pending") {
            const createdAt = Number(localFocusIntent.created_at || 0);
            if (createdAt > 0 && (Date.now() / 1000) - createdAt > 5) {
                localFocusIntent = null;
                return null;
            }
            return localFocusIntent;
        }
        return null;
    }

    function pendingFocusIntentFor(kind) {
        const intent = pendingFocusIntent();
        return intent && stringOrEmpty(intent.kind) === stringOrEmpty(kind) ? intent : null;
    }

    function localPendingFocusIntentFor(kind) {
        if (!localFocusIntent || stringOrEmpty(localFocusIntent.state) !== "pending") {
            return null;
        }
        const createdAt = Number(localFocusIntent.created_at || 0);
        if (createdAt > 0 && (Date.now() / 1000) - createdAt > 5) {
            localFocusIntent = null;
            return null;
        }
        return stringOrEmpty(localFocusIntent.kind) === stringOrEmpty(kind) ? localFocusIntent : null;
    }

    function focusIntentMatchesTarget(intent, targetKey) {
        const normalizedTargetKey = stringOrEmpty(targetKey);
        return !!intent
            && normalizedTargetKey !== ""
            && stringOrEmpty(intent.target_key) === normalizedTargetKey;
    }

    function pendingFocusIntentMatches(kind, targetKey) {
        const intent = pendingFocusIntentFor(kind);
        return focusIntentMatchesTarget(intent, targetKey);
    }

    function focusIntentKindAndTarget(method, params) {
        const normalizedMethod = stringOrEmpty(method);
        const payload = params && typeof params === "object" ? params : {};
        if (normalizedMethod === "window.focus" || normalizedMethod === "window.focus_fast") {
            const windowId = Number(payload.window_id || 0);
            return windowId > 0 ? {kind: "window_focus", target_key: String(windowId)} : null;
        }
        if (normalizedMethod === "workspace.focus" || normalizedMethod === "workspace.focus_fast") {
            const workspace = stringOrEmpty(payload.workspace);
            return workspace ? {kind: "workspace_focus", target_key: workspace} : null;
        }
        if (normalizedMethod === "herdr.pane.focus" || normalizedMethod === "herdr.remote.pane.focus") {
            const paneId = stringOrEmpty(payload.pane_id);
            if (!paneId) {
                return null;
            }
            const host = stringOrEmpty(payload.host || payload.ssh_target);
            return {kind: "herdr_pane_focus", target_key: host ? host + ":" + paneId : paneId};
        }
        if (normalizedMethod === "herdr.workspace.focus") {
            const workspaceId = stringOrEmpty(payload.workspace_id);
            return workspaceId ? {kind: "herdr_workspace_focus", target_key: workspaceId} : null;
        }
        return null;
    }

    function beginLocalFocusIntent(method, params) {
        const intentTarget = focusIntentKindAndTarget(method, params);
        if (!intentTarget) {
            return;
        }
        localFocusIntent = {
            intent_id: "local-" + Date.now(),
            kind: intentTarget.kind,
            target_key: intentTarget.target_key,
            state: "pending",
            created_at: Date.now() / 1000,
            generation: dashboardGeneration(dashboard),
        };
    }

    function localFocusIntentMatches(intent) {
        return !!localFocusIntent
            && !!intent
            && stringOrEmpty(localFocusIntent.kind) === stringOrEmpty(intent.kind)
            && stringOrEmpty(localFocusIntent.target_key) === stringOrEmpty(intent.target_key);
    }

    function clearLocalFocusIntentIfSettled() {
        if (!localFocusIntent) {
            return;
        }
        const kind = stringOrEmpty(localFocusIntent.kind);
        const targetKey = stringOrEmpty(localFocusIntent.target_key);
        const focusState = dashboardFocusState();
        if (kind === "workspace_focus" && targetKey === stringOrEmpty(focusState.current_workspace_name)) {
            localFocusIntent = null;
            return;
        }
        if (kind === "window_focus" && targetKey === String(Number(focusState.current_window_id || 0))) {
            localFocusIntent = null;
            return;
        }
        if (kind === "herdr_pane_focus") {
            const paneId = stringOrEmpty(focusState.current_herdr_pane_id);
            const host = stringOrEmpty(focusState.current_herdr_host);
            if (targetKey === paneId || (host && targetKey === host + ":" + paneId)) {
                localFocusIntent = null;
            }
        }
    }

    function sessionPendingFocusTargetKey(session, intent) {
        const paneId = stringOrEmpty(session && session.pane_id);
        if (!paneId) {
            return "";
        }

        const activeIntent = intent || pendingFocusIntent();
        const targetKey = stringOrEmpty(activeIntent && activeIntent.target_key);
        if (targetKey.indexOf(":") < 0) {
            return paneId;
        }

        const focusTarget = session && typeof session.focus_target === "object" ? session.focus_target : {};
        const params = focusTarget && typeof focusTarget.params === "object" ? focusTarget.params : {};
        const host = stringOrEmpty(params.host || params.ssh_target || session.host_name || session.target_host);
        return host ? host + ":" + paneId : "";
    }

    function windowIsFocused(windowData) {
        const windowId = windowIdValue(windowData);
        const pendingWindowFocus = pendingFocusIntentFor("window_focus");
        if (pendingWindowFocus) {
            return pendingFocusIntentMatches("window_focus", String(windowId));
        }
        const currentWindowId = Number(dashboardFocusState().current_window_id || 0);
        return windowId > 0 && currentWindowId > 0 && windowId === currentWindowId;
    }

    function windowIsCurrentTarget(windowData) {
        return windowIsFocused(windowData);
    }

    function sessionIsDisplayEligible(session) {
        if (!session || typeof session !== "object") {
            return false;
        }

        if (stringOrEmpty(session.source) === "herdr" || stringOrEmpty(session.pane_id)) {
            return stringOrEmpty(session.pane_id).length > 0;
        }

        return false;
    }

    function sessionIsPanelDisplayEligible(session) {
        if (!session || typeof session !== "object") {
            return false;
        }

        if (stringOrEmpty(session.source) === "herdr" || stringOrEmpty(session.pane_id)) {
            return stringOrEmpty(session.pane_id).length > 0;
        }

        return false;
    }

    function stableSessionCompare(left, right) {
        let result = compareDescending(sessionIsCurrentHost(left) ? 1 : 0, sessionIsCurrentHost(right) ? 1 : 0);
        if (result !== 0) {
            return result;
        }

        result = compareAscending(sessionHostGroupKey(left), sessionHostGroupKey(right));
        if (result !== 0) {
            return result;
        }

        result = compareAscending(sessionPaneSlot(left), sessionPaneSlot(right));
        if (result !== 0) {
            return result;
        }

        result = compareAscending(sessionWindowSlot(left), sessionWindowSlot(right));
        if (result !== 0) {
            return result;
        }

        result = compareAscending(stringOrEmpty(left && left.pane_label), stringOrEmpty(right && right.pane_label));
        if (result !== 0) {
            return result;
        }

        result = compareAscending(stringOrEmpty(left && left.tool), stringOrEmpty(right && right.tool));
        if (result !== 0) {
            return result;
        }

        return compareAscending(sessionIdentityKey(left), sessionIdentityKey(right));
    }

    function stableSortedSessions(items) {
        const sessions = uniqueSessions(items).slice();
        sessions.sort((left, right) => stableSessionCompare(left, right));
        return sessions;
    }

    function projectGroupFor(projectName, targetHost) {
        const projects = arrayOrEmpty(dashboard.projects);
        const project = stringOrEmpty(projectName);
        const host = normalizeHostAlias(targetHost || currentHostAlias());

        return projects.find(projectGroup => stringOrEmpty(projectGroup.project) === project && normalizeHostAlias(projectGroup.target_host || shellConfig.hostName) === host) || null;
    }

    function focusPreferredWindowForContext(projectName, targetHost) {
        const projectGroup = projectGroupFor(projectName, targetHost);
        if (!projectGroup) {
            return false;
        }

        const windows = arrayOrEmpty(projectGroup.windows).filter(windowData => !boolOrFalse(windowData.hidden));
        if (!windows.length) {
            return false;
        }

        const focusedWindow = windows.find(windowData => windowIsFocused(windowData));
        focusWindow(focusedWindow || windows[0]);
        return true;
    }

    function primaryOutputCandidates() {
        return arrayOrEmpty(shellConfig.primaryOutputs).map(value => stringOrEmpty(value)).filter(value => value);
    }

    // True when at least one configured primary output is currently an active
    // screen. False in clamshell mode (eDP-1 disabled, external not a candidate),
    // which is the cue to fall back to the focused monitor for floating windows.
    function configuredPrimaryActive() {
        const candidates = primaryOutputCandidates();
        for (let i = 0; i < candidates.length; i += 1) {
            if (findScreenByOutputName(candidates[i])) {
                return true;
            }
        }
        return false;
    }

    function findScreenByOutputName(outputName) {
        const target = stringOrEmpty(outputName);
        if (!target) {
            return null;
        }

        const screens = arrayOrEmpty(Quickshell.screens);
        for (let i = 0; i < screens.length; i += 1) {
            const screen = screens[i];
            if (screenOutputName(screen) === target) {
                return screen;
            }
        }

        return null;
    }

    function monitorForScreen(screen) {
        if (!screen) {
            return null;
        }
        try {
            return I3.monitorFor(screen);
        } catch (_error) {
            return null;
        }
    }

    function screenOutputName(screen) {
        const monitor = monitorForScreen(screen);
        const monitorName = stringOrEmpty(monitor ? monitor.name : "");
        if (monitorName) {
            return monitorName;
        }
        return stringOrEmpty(screen ? screen.name : "");
    }

    function notificationToastOuterMargin() {
        return 18;
    }

    function notificationToastTopInset() {
        return shellConfig.topBarHeight + notificationToastOuterMargin();
    }

    function notificationToastRightInset(outputName) {
        let inset = notificationToastOuterMargin();
        if (panelVisible && stringOrEmpty(outputName) === primaryOutputName) {
            inset += shellConfig.panelWidth + 12;
        }
        return inset;
    }

    function notificationToastWidthForScreen(screen, outputName) {
        const fallbackWidth = 380;
        const screenWidth = Number(screen && screen.width || 0);

        if (screenWidth <= 0) {
            return fallbackWidth;
        }

        const availableWidth = screenWidth - notificationToastOuterMargin() - notificationToastRightInset(outputName);
        if (availableWidth <= 0) {
            return fallbackWidth;
        }

        return Math.max(1, Math.min(fallbackWidth, availableWidth));
    }

    function livePrimaryOutputName() {
        const displayLayout = dashboard.display_layout || {};
        const outputs = arrayOrEmpty(displayLayout.outputs);

        for (let i = 0; i < outputs.length; i += 1) {
            const output = outputs[i];
            if (!output || !output.primary || !output.active || output.enabled === false) {
                continue;
            }

            const name = stringOrEmpty(output.name);
            if (name) {
                return name;
            }
        }

        return "";
    }

    function displayLayoutState() {
        return dashboard && typeof dashboard === "object" && dashboard.display_layout
            ? dashboard.display_layout
            : {};
    }

    function resolvePrimaryScreen() {
        const screens = arrayOrEmpty(Quickshell.screens);
        if (!screens.length) {
            return null;
        }

        const candidates = primaryOutputCandidates();
        for (let i = 0; i < candidates.length; i += 1) {
            const preferredScreen = findScreenByOutputName(candidates[i]);
            if (preferredScreen) {
                return preferredScreen;
            }
        }

        const livePrimaryScreen = findScreenByOutputName(livePrimaryOutputName());
        if (livePrimaryScreen) {
            return livePrimaryScreen;
        }

        const focusedMonitor = I3.focusedMonitor;
        const focusedScreen = findScreenByOutputName(stringOrEmpty(focusedMonitor ? focusedMonitor.name : ""));
        if (focusedScreen) {
            return focusedScreen;
        }

        return screens[0];
    }

    function dashboardWorkspacesForOutput(outputName) {
        const outputs = arrayOrEmpty(dashboard.outputs);
        const target = stringOrEmpty(outputName);
        const items = [];

        for (let i = 0; i < outputs.length; i += 1) {
            const output = outputs[i];
            if (stringOrEmpty(output ? output.name : "") !== target) {
                continue;
            }

            const workspaces = arrayOrEmpty(output.workspaces);
            for (let j = 0; j < workspaces.length; j += 1) {
                const workspace = workspaces[j];
                const name = stringOrEmpty(workspace ? workspace.name : "");
                if (name.indexOf("scratchpad") === 0) {
                    continue;
                }
                const focused = workspaceIsFocused(name);
                const windows = arrayOrEmpty(workspace ? workspace.windows : []);
                const visible = boolOrFalse(workspace?.visible);
                const hasWindows = windows.length > 0;
                if (!focused && !visible && !hasWindows) {
                    continue;
                }
                items.push({
                    num: Number(workspace?.number || 0),
                    name: name,
                    label: name,
                    focused: focused,
                    active: focused || visible || hasWindows,
                    urgent: boolOrFalse(workspace?.urgent),
                    window_count: windows.length,
                    icon_sources: workspaceIconSourcesForWindows(windows),
                    configured: boolOrFalse(workspace?.configured),
                    monitor_role: stringOrEmpty(workspace?.monitor_role),
                    app_name: stringOrEmpty(workspace?.app_name),
                    app_names: arrayOrEmpty(workspace?.app_names),
                    output: target
                });
            }
            break;
        }

        items.sort((left, right) => Number(left?.num || 0) - Number(right?.num || 0));
        return items;
    }

    function barWorkspacesForOutput(outputName) {
        // Single source of truth: the i3pm daemon snapshot (dashboard.outputs).
        // The daemon owns the i3ipc connection and now pushes `outputs` live on
        // every workspace-membership change, so the bar renders purely from it.
        // No compositor-side fallback (Quickshell's I3.workspaces) — a second,
        // independently-tracked source could disagree with the daemon and
        // render phantom or missing workspaces. Before the first snapshot (or
        // while the daemon is unreachable) this returns [] and the workspace
        // strip is empty, matching the rest of the daemon-sourced bar.
        return dashboardWorkspacesForOutput(outputName);
    }

    function currentLayoutLabel() {
        const displayLayout = displayLayoutState();
        const layout = stringOrEmpty(displayLayout.current_layout);
        if (layout) {
            return layout;
        }
        return primaryOutputName || "Display";
    }

    function displayLayoutOptions() {
        const displayLayout = displayLayoutState();
        const options = arrayOrEmpty(displayLayout.layout_options);
        if (options.length > 0) {
            return options;
        }

        const names = arrayOrEmpty(displayLayout.layouts);
        const current = stringOrEmpty(displayLayout.current_layout);
        const items = [];
        for (let i = 0; i < names.length; i += 1) {
            const name = stringOrEmpty(names[i]);
            if (!name) {
                continue;
            }
            items.push({
                name: name,
                label: name.replace(/[-_]+/g, " ").replace(/\b\w/g, function (match) {
                    return match.toUpperCase();
                }),
                description: "",
                output_names: [],
                output_count: 0,
                current: name === current
            });
        }
        return items;
    }

    function displayOptionName(option) {
        return stringOrEmpty(option && option.name);
    }

    function displayOptionLabel(option) {
        return stringOrEmpty(option && option.label) || displayOptionName(option) || "Layout";
    }

    function displayOptionDescription(option) {
        const description = stringOrEmpty(option && option.description);
        if (description) {
            return description;
        }
        const outputCount = Number(option && option.output_count || 0);
        if (outputCount > 0) {
            return String(outputCount) + (outputCount === 1 ? " monitor enabled" : " monitors enabled");
        }
        return "Daemon-backed display preset";
    }

    function displayOptionOutputs(option) {
        return arrayOrEmpty(option && option.output_names).filter(function (name) {
            return stringOrEmpty(name) !== "";
        });
    }

    function activeDisplayOutputs() {
        const outputs = arrayOrEmpty(displayLayoutState().outputs);
        return outputs.filter(function (output) {
            return !!(output && output.active) && output.enabled !== false;
        });
    }

    function allDisplayOutputs() {
        // Every connected output, including ones currently disabled (active: false)
        // so they stay toggleable from the dialog — disabling a monitor must not
        // remove its own re-enable control.
        const outputs = arrayOrEmpty(displayLayoutState().outputs);
        return outputs.filter(function (output) {
            return !!(output && stringOrEmpty(output.name));
        });
    }

    function displayHasGeometry(output) {
        return !!(output && output.rect
            && Number(output.rect.width) > 0
            && Number(output.rect.height) > 0);
    }

    function displayMapOutputs() {
        // Connected outputs that currently occupy space (enabled + positioned).
        return allDisplayOutputs().filter(function (output) {
            return displayHasGeometry(output);
        });
    }

    function displayOffOutputs() {
        // Connected but disabled outputs (no geometry) — shown as re-enable chips.
        return allDisplayOutputs().filter(function (output) {
            return !displayHasGeometry(output);
        });
    }

    function enabledDisplayCount() {
        return displayMapOutputs().length;
    }

    function displayMapBoxes(cw, ch) {
        // Project the enabled outputs' real pixel rects into a uniformly-scaled,
        // centered mini-map of size cw x ch, so the popup shows the true physical
        // arrangement (the same coordinates lid-clamshell lays out).
        const outs = displayMapOutputs();
        const boxes = [];
        if (!outs.length || cw <= 0 || ch <= 0) {
            return boxes;
        }
        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        for (let i = 0; i < outs.length; i += 1) {
            const r = outs[i].rect;
            const x = Number(r.x) || 0, y = Number(r.y) || 0;
            const w = Number(r.width) || 0, h = Number(r.height) || 0;
            if (x < minX) minX = x;
            if (y < minY) minY = y;
            if (x + w > maxX) maxX = x + w;
            if (y + h > maxY) maxY = y + h;
        }
        const spanX = Math.max(1, maxX - minX);
        const spanY = Math.max(1, maxY - minY);
        const pad = 6;
        const scale = Math.min((cw - 2 * pad) / spanX, (ch - 2 * pad) / spanY);
        const offX = pad + ((cw - 2 * pad) - spanX * scale) / 2;
        const offY = pad + ((ch - 2 * pad) - spanY * scale) / 2;
        for (let i = 0; i < outs.length; i += 1) {
            const o = outs[i];
            const r = o.rect;
            boxes.push({
                name: stringOrEmpty(o.name),
                label: displayFriendlyName(o),
                enabled: o.enabled !== false,
                primary: !!o.primary,
                resolution: (Number(r.width) || 0) + "×" + (Number(r.height) || 0),
                x: offX + ((Number(r.x) || 0) - minX) * scale,
                y: offY + ((Number(r.y) || 0) - minY) * scale,
                w: Math.max(12, (Number(r.width) || 0) * scale - 2),
                h: Math.max(12, (Number(r.height) || 0) * scale - 2)
            });
        }
        return boxes;
    }

    function displayFriendlyName(output) {
        const name = stringOrEmpty(output && output.name);
        const make = stringOrEmpty(output && output.make).toLowerCase();
        const model = stringOrEmpty(output && output.model).toLowerCase();
        if (name === "eDP-1" || make.indexOf("boe") !== -1) {
            return "ThinkPad";
        }
        if (model.indexOf("verbatim") !== -1 || model.indexOf("mt17") !== -1) {
            return "Verbatim";
        }
        if (make.indexOf("samsung") !== -1 || model.indexOf("samsung") !== -1) {
            return "Samsung";
        }
        return name;
    }

    function displayRoleOfOutput(output) {
        const make = stringOrEmpty(output && output.make).toLowerCase();
        const model = stringOrEmpty(output && output.model).toLowerCase();
        if (model.indexOf("verbatim") !== -1 || model.indexOf("mt17") !== -1) {
            return "verbatim";
        }
        if (make.indexOf("samsung") !== -1 || model.indexOf("samsung") !== -1) {
            return "samsung";
        }
        return "";
    }

    function displayPresets() {
        // Role-based presets, resolved deterministically by lid-clamshell.
        return [
            { id: "all", label: "All" },
            { id: "verbatim", label: "+ Verbatim" },
            { id: "samsung", label: "+ Samsung" },
            { id: "laptop", label: "Laptop only" }
        ];
    }

    function displayRolesPresent(outputs) {
        let verb = false, sam = false;
        for (let i = 0; i < outputs.length; i += 1) {
            const role = displayRoleOfOutput(outputs[i]);
            if (role === "verbatim") {
                verb = true;
            } else if (role === "samsung") {
                sam = true;
            }
        }
        return { verbatim: verb, samsung: sam };
    }

    function activeDisplayPresetId() {
        // Which preset matches the currently enabled (positioned) outputs.
        const roles = displayRolesPresent(displayMapOutputs());
        if (roles.verbatim && roles.samsung) {
            return "all";
        }
        if (roles.verbatim) {
            return "verbatim";
        }
        if (roles.samsung) {
            return "samsung";
        }
        return "laptop";
    }

    function displayPresetAvailable(presetId) {
        // Only offer presets whose monitor is actually connected.
        const roles = displayRolesPresent(allDisplayOutputs());
        if (presetId === "verbatim") {
            return roles.verbatim;
        }
        if (presetId === "samsung") {
            return roles.samsung;
        }
        if (presetId === "all") {
            return roles.verbatim || roles.samsung;
        }
        return true; // "laptop" is always available
    }

    function displayPresetPending(presetId) {
        const target = stringOrEmpty(displayPresetTarget);
        return target !== "" && target === stringOrEmpty(presetId);
    }

    function applyDisplayPreset(presetId) {
        const target = stringOrEmpty(presetId);
        if (!target) {
            return;
        }
        if (!displayPresetProcess || displayPresetProcess.running) {
            return;
        }
        if (activeDisplayPresetId() === target) {
            return;
        }
        displayPresetTarget = target;
        displayPresetProcess.command = [shellConfig.lidClamshellBin, "preset", target];
        displayPresetProcess.running = true;
    }

    function toggleDisplayOutput(outputName) {
        if (!displayToggleOutputProcess || displayToggleOutputProcess.running) {
            return;
        }
        displayToggleTarget = outputName;
        displayToggleStdout = "";
        displayToggleStderr = "";
        displayToggleOutputProcess.command = [shellConfig.i3pmBin, "display", "toggle-output", outputName];
        displayToggleOutputProcess.running = true;
    }

    function displayTogglePending(outputName) {
        return displayToggleTarget !== "" && displayToggleTarget === stringOrEmpty(outputName);
    }

    function setDisplayScale(outputName, scale) {
        if (!displayScaleProcess || displayScaleProcess.running) {
            return;
        }
        displayScaleTarget = outputName;
        displayScaleStdout = "";
        displayScaleStderr = "";
        displayScaleProcess.command = [shellConfig.i3pmBin, "display", "set-scale", outputName, String(scale)];
        displayScaleProcess.running = true;
    }

    function displayScalePending(outputName) {
        return displayScaleTarget !== "" && displayScaleTarget === stringOrEmpty(outputName);
    }

    function updateDisplayLayoutFromSnapshot(snapshot) {
        if (!snapshot || !snapshot.outputs) {
            return;
        }
        var state = displayLayoutState();
        state.outputs = snapshot.outputs;
        if (snapshot.current_layout !== undefined) {
            state.current_layout = snapshot.current_layout;
        }
        if (snapshot.layouts !== undefined) {
            state.layouts = snapshot.layouts;
        }
        if (snapshot.layout_options !== undefined) {
            state.layout_options = snapshot.layout_options;
        }
        displayLayoutStateChanged();
    }

    function activeDisplayOutputNames() {
        return activeDisplayOutputs().map(function (output) {
            return stringOrEmpty(output && output.name);
        }).filter(function (name) {
            return name !== "";
        });
    }

    function activeDisplaySummary() {
        const names = activeDisplayOutputNames();
        if (!names.length) {
            return "No managed outputs reported";
        }
        return names.join("  •  ");
    }

    function displayApplyPending(layoutName) {
        const target = stringOrEmpty(layoutName);
        return target !== ""
            && target === stringOrEmpty(displayApplyTarget)
            && !!(displayApplyProcess && displayApplyProcess.running);
    }

    function clearDisplayApplyState() {
        displayApplyTarget = "";
        displayApplyStdout = "";
        displayApplyStderr = "";
        displayApplyError = "";
    }

    function syncDisplayApplyStateFromDashboard() {
        const target = stringOrEmpty(displayApplyTarget);
        if (!target) {
            return;
        }

        if (stringOrEmpty(displayLayoutState().current_layout) === target) {
            clearDisplayApplyState();
            displaySelectorVisible = false;
            displaySelectorOutputName = "";
        }
    }

    function displayApplyStatusText() {
        if (displayApplyError) {
            return displayApplyError;
        }
        if (displayApplyTarget) {
            return "Applying " + displayApplyTarget + "...";
        }
        if (displayPresetTarget) {
            return "Switching to " + displayPresetTarget + "...";
        }
        return "Pick a configuration, or tap a screen to toggle it.";
    }

    function openDisplaySelector(outputName) {
        // Open the popup as long as there's anything to control — either layout
        // presets or per-output enable/scale toggles. (After the VNC/iPad profile
        // removal there are no presets on the ThinkPad; the popup is purely the
        // per-monitor enable/disable + scale controls.)
        if (displayLayoutOptions().length === 0 && allDisplayOutputs().length === 0) {
            openSettings("devices");
            return;
        }
        const targetOutput = stringOrEmpty(outputName) || primaryOutputName || focusedOutputName() || "";
        powerMenuVisible = false;
        audioPopupVisible = false;
        bluetoothPopupVisible = false;
        displaySelectorOutputName = targetOutput;
        displaySelectorVisible = true;
    }

    function closeDisplaySelector() {
        displaySelectorVisible = false;
        displaySelectorOutputName = "";
    }

    // Close every top-bar chip popup (volume / bluetooth / power / displays).
    // Used by the click-away backdrop so any of them dismisses on an outside click.
    function closeBarPopups() {
        audioPopupVisible = false;
        bluetoothPopupVisible = false;
        powerMenuVisible = false;
        displaySelectorVisible = false;
        displaySelectorOutputName = "";
    }

    // Whether any top-bar chip popup is currently open on the given output (drives
    // the per-monitor click-away backdrop's visibility). audio/bluetooth/power use
    // barPopupOutputName; the display selector tracks its own output.
    function anyBarPopupOpenOnOutput(outputName) {
        const o = stringOrEmpty(outputName);
        if ((audioPopupVisible || bluetoothPopupVisible || powerMenuVisible)
            && stringOrEmpty(barPopupOutputName) === o) {
            return true;
        }
        if (displaySelectorVisible && stringOrEmpty(displaySelectorOutputName) === o) {
            return true;
        }
        return false;
    }

    function applyDisplayLayout(layoutName) {
        const target = stringOrEmpty(layoutName);
        if (!target) {
            return;
        }
        if (stringOrEmpty(displayLayoutState().current_layout) === target) {
            closeDisplaySelector();
            return;
        }
        if (!displayApplyProcess || displayApplyProcess.running) {
            return;
        }
        displayApplyTarget = target;
        displayApplyStdout = "";
        displayApplyStderr = "";
        displayApplyError = "";
        displayApplyProcess.command = [shellConfig.i3pmBin, "display", "apply", target];
        displayApplyProcess.running = true;
    }

    function focusedOutputName() {
        return stringOrEmpty(I3.focusedMonitor ? I3.focusedMonitor.name : "");
    }

    function isPrimaryOutput(outputName) {
        return stringOrEmpty(outputName) !== "" && stringOrEmpty(outputName) === primaryOutputName;
    }

    function isFocusedOutput(outputName) {
        return stringOrEmpty(outputName) !== "" && stringOrEmpty(outputName) === focusedOutputName();
    }

    function notificationsBackendNative() {
        return stringOrEmpty(shellConfig.notificationBackend).toLowerCase() === "native";
    }

    function notificationTargetOutputName() {
        return focusedOutputName() || primaryOutputName || stringOrEmpty(shellConfig.hostName);
    }

    function notificationBodyFormat() {
        return shellConfig.notificationMarkupEnabled ? Text.StyledText : Text.PlainText;
    }

    function notificationActionIdentifier(action) {
        return stringOrEmpty(action && action.identifier);
    }

    function notificationActionText(action) {
        return stringOrEmpty(action && action.text) || "Open";
    }

    function notificationUnread(item) {
        return boolOrFalse(item && item.unread);
    }

    function notificationClosed(item) {
        return boolOrFalse(item && item.closed);
    }

    function notificationIsCritical(item) {
        return stringOrEmpty(item && item.urgency).toLowerCase() === "critical";
    }

    function notificationHasActions(item) {
        return arrayOrEmpty(item && item.actions).length > 0;
    }

    function notificationPrimaryAction(item) {
        const actions = arrayOrEmpty(item && item.actions);
        return actions.length > 0 ? actions[0] : null;
    }

    function notificationAppLabel(item) {
        const appName = stringOrEmpty(item && item.app_name);
        const desktopEntry = stringOrEmpty(item && item.desktop_entry);
        if (appName) {
            return appName;
        }
        if (desktopEntry) {
            return desktopEntry;
        }
        return "Notification";
    }

    function notificationHeadline(item) {
        const summary = stringOrEmpty(item && item.summary);
        if (summary) {
            return summary;
        }
        return notificationAppLabel(item);
    }

    function notificationBody(item) {
        return stringOrEmpty(item && item.body);
    }

    function notificationAvatarText(item) {
        const label = notificationAppLabel(item);
        return label ? label.slice(0, 1).toUpperCase() : "•";
    }

    function notificationResolvedIcon(item) {
        const appIcon = stringOrEmpty(item && item.app_icon);
        if (appIcon) {
            return Quickshell.iconPath(appIcon, true) || appIcon;
        }

        const desktopEntry = stringOrEmpty(item && item.desktop_entry);
        if (desktopEntry) {
            return Quickshell.iconPath(desktopEntry, true);
        }

        return "";
    }

    function notificationResolvedImage(item) {
        if (!shellConfig.notificationImagesEnabled) {
            return "";
        }
        return stringOrEmpty(item && item.image);
    }

    function notificationAccentColor(item) {
        if (notificationIsCritical(item)) {
            return colors.red;
        }
        if (notificationHasActions(item)) {
            return colors.teal;
        }
        if (notificationUnread(item)) {
            return colors.blue;
        }
        return colors.violet;
    }

    function notificationAvatarFill(item) {
        if (notificationIsCritical(item)) {
            return colors.redBg;
        }
        if (notificationHasActions(item)) {
            return colors.tealBg;
        }
        if (notificationUnread(item)) {
            return colors.blueBg;
        }
        return colors.panelAlt;
    }

    function notificationCardFill(item) {
        if (notificationIsCritical(item)) {
            return colors.redBg;
        }
        if (notificationUnread(item)) {
            return colors.blueWash;
        }
        return colors.cardAlt;
    }

    function notificationCardBorder(item) {
        if (notificationIsCritical(item)) {
            return colors.red;
        }
        if (notificationUnread(item)) {
            return colors.blueMuted;
        }
        return colors.lineSoft;
    }

    function notificationMetaLabel(item) {
        const parts = [];
        const appLabel = notificationAppLabel(item);
        if (appLabel) {
            parts.push(appLabel);
        }
        const outputName = stringOrEmpty(item && item.output_name);
        if (outputName) {
            parts.push(outputName);
        }
        const closedReason = stringOrEmpty(item && item.closed_reason);
        if (closedReason) {
            parts.push(closedReason);
        } else if (notificationUnread(item)) {
            parts.push("Unread");
        } else if (notificationClosed(item)) {
            parts.push("Seen");
        } else {
            parts.push("Live");
        }
        return parts.join(" • ");
    }

    function notificationDisplayCount(count) {
        const value = Number(count || 0);
        if (value > 9) {
            return "9+";
        }
        return String(Math.max(0, value));
    }

    function notificationUnreadCount() {
        return notificationFeed.filter(item => notificationUnread(item)).length;
    }

    function visibleNotificationItems() {
        return notificationFeed.filter(item => !notificationClosed(item));
    }

    function notificationPanelItems() {
        return notificationFeed.slice(0, Math.max(1, Number(shellConfig.notificationHistoryLimit || 80)));
    }

    function notificationHeroItem() {
        const live = visibleNotificationItems();
        if (live.length > 0) {
            return live[0];
        }
        return notificationFeed.length > 0 ? notificationFeed[0] : null;
    }

    function toastItemsForOutput(outputName) {
        const toastLimit = Math.max(0, Number(shellConfig.notificationToastMaxPerOutput || 0));
        const candidates = notificationFeed.filter(item => !notificationClosed(item) && boolOrFalse(item.toast_visible) && stringOrEmpty(item.output_name) === stringOrEmpty(outputName));
        return toastLimit > 0 ? candidates.slice(0, toastLimit) : [];
    }

    function refreshNotificationState() {
        const unreadCount = notificationUnreadCount();
        notificationState = {
            count: unreadCount,
            dnd: notificationDnd,
            visible: notificationCenterVisible,
            inhibited: false,
            has_unread: unreadCount > 0,
            display_count: notificationDisplayCount(unreadCount),
            error: false
        };
    }

    function replaceNotificationItem(updatedItem) {
        const next = [];
        let replaced = false;
        for (let i = 0; i < notificationFeed.length; i += 1) {
            const item = notificationFeed[i];
            if (Number(item && item.id) === Number(updatedItem && updatedItem.id)) {
                next.push(updatedItem);
                replaced = true;
            } else {
                next.push(item);
            }
        }
        if (!replaced) {
            next.unshift(updatedItem);
        }
        notificationFeed = next.slice(0, Math.max(1, Number(shellConfig.notificationHistoryLimit || 80)));
        refreshNotificationState();
    }

    function markNotificationRead(notificationId) {
        const targetId = Number(notificationId || 0);
        if (!targetId) {
            return;
        }
        for (let i = 0; i < notificationFeed.length; i += 1) {
            const item = notificationFeed[i];
            if (Number(item && item.id) !== targetId || !notificationUnread(item)) {
                continue;
            }
            replaceNotificationItem({
                id: item.id,
                app_name: item.app_name,
                app_icon: item.app_icon,
                desktop_entry: item.desktop_entry,
                summary: item.summary,
                body: item.body,
                urgency: item.urgency,
                output_name: item.output_name,
                image: item.image,
                unread: false,
                closed: item.closed,
                closed_reason: item.closed_reason,
                toast_visible: item.toast_visible,
                actions: arrayOrEmpty(item.actions)
            });
            break;
        }
    }

    function markAllNotificationsRead() {
        let changed = false;
        const next = notificationFeed.map(item => {
            if (!notificationUnread(item)) {
                return item;
            }
            changed = true;
            return {
                id: item.id,
                app_name: item.app_name,
                app_icon: item.app_icon,
                desktop_entry: item.desktop_entry,
                summary: item.summary,
                body: item.body,
                urgency: item.urgency,
                output_name: item.output_name,
                image: item.image,
                unread: false,
                closed: item.closed,
                closed_reason: item.closed_reason,
                toast_visible: item.toast_visible,
                actions: arrayOrEmpty(item.actions)
            };
        });
        if (changed) {
            notificationFeed = next;
        }
        refreshNotificationState();
    }

    function clearNotifications() {
        const ids = notificationFeed.map(item => Number(item && item.id)).filter(id => id > 0);
        for (let i = 0; i < ids.length; i += 1) {
            dismissNotification(ids[i]);
        }
        notificationFeed = [];
        notificationRuntimeMap = ({});
        refreshNotificationState();
    }

    function notificationTimeoutFor(item) {
        if (notificationIsCritical(item)) {
            return Number(shellConfig.notificationCriticalTimeoutMs || 0);
        }
        return Number(item && item.timeout_ms) > 0 ? Number(item.timeout_ms) : Number(shellConfig.notificationDefaultTimeoutMs || 8000);
    }

    function dismissNotification(notificationId) {
        const targetId = Number(notificationId || 0);
        if (!targetId) {
            return;
        }
        const notification = notificationRuntimeMap[String(targetId)];
        if (notification) {
            notification.dismiss();
        } else {
            for (let i = 0; i < notificationFeed.length; i += 1) {
                const item = notificationFeed[i];
                if (Number(item && item.id) !== targetId) {
                    continue;
                }
                replaceNotificationItem({
                    id: item.id,
                    app_name: item.app_name,
                    app_icon: item.app_icon,
                    desktop_entry: item.desktop_entry,
                    summary: item.summary,
                    body: item.body,
                    urgency: item.urgency,
                    output_name: item.output_name,
                    image: item.image,
                    unread: false,
                    closed: true,
                    closed_reason: "Dismissed",
                    toast_visible: false,
                    actions: arrayOrEmpty(item.actions)
                });
                break;
            }
        }
    }

    function expireNotification(notificationId) {
        const targetId = Number(notificationId || 0);
        if (!targetId) {
            return;
        }
        const notification = notificationRuntimeMap[String(targetId)];
        if (notification) {
            notification.expire();
        }
    }

    function invokeNotificationAction(notificationId, actionId) {
        const targetId = Number(notificationId || 0);
        const notification = notificationRuntimeMap[String(targetId)];
        if (!notification) {
            return;
        }
        const actions = arrayOrEmpty(notification.actions);
        for (let i = 0; i < actions.length; i += 1) {
            const action = actions[i];
            if (notificationActionIdentifier(action) !== stringOrEmpty(actionId)) {
                continue;
            }
            markNotificationRead(targetId);
            action.invoke();
            break;
        }
    }

    function showNotificationDetail(id) {
        var feed = arrayOrEmpty(notificationFeed);
        for (var i = 0; i < feed.length; i += 1) {
            if (Number(feed[i] && feed[i].id) === id) {
                notificationDetailItem = feed[i];
                notificationDetailVisible = true;
                return;
            }
        }
    }

    function hideNotificationDetail() {
        notificationDetailVisible = false;
        notificationDetailItem = null;
    }

    function toggleNotifications() {
        panelVisible = true;
        notificationCenterVisible = !notificationCenterVisible;
    }

    function toggleNotificationDnd() {
        notificationDnd = !notificationDnd;
        refreshNotificationState();
    }

    function connectNotificationLifecycle(notification) {
        const targetId = Number(notification && notification.id);
        if (!targetId) {
            return;
        }
        if (notificationLifecycleConnected[String(targetId)]) {
            return;
        }
        notificationLifecycleConnected = Object.assign({}, notificationLifecycleConnected, {
            [String(targetId)]: true
        });
        notification.closed.connect(function(reason) {
            const reasonLabel = String(reason).indexOf("Expired") >= 0 ? "Expired" : (String(reason).indexOf("Dismissed") >= 0 ? "Dismissed" : "Closed");
            delete notificationRuntimeMap[String(targetId)];
            delete notificationLifecycleConnected[String(targetId)];
            for (let i = 0; i < notificationFeed.length; i += 1) {
                const item = notificationFeed[i];
                if (Number(item && item.id) !== targetId) {
                    continue;
                }
                replaceNotificationItem({
                    id: item.id,
                    app_name: item.app_name,
                    app_icon: item.app_icon,
                    desktop_entry: item.desktop_entry,
                    summary: item.summary,
                    body: item.body,
                    urgency: item.urgency,
                    output_name: item.output_name,
                    image: item.image,
                    unread: item.unread,
                    closed: true,
                    closed_reason: reasonLabel,
                    toast_visible: false,
                    timeout_ms: item.timeout_ms,
                    actions: arrayOrEmpty(item.actions)
                });
                break;
            }
        });
    }

    function handleNativeNotification(notification) {
        const targetId = Number(notification && notification.id);
        if (!targetId) {
            return;
        }

        notification.tracked = true;
        notificationRuntimeMap = Object.assign({}, notificationRuntimeMap, {
            [String(targetId)]: notification
        });

        connectNotificationLifecycle(notification);

        const snapshot = {
            id: targetId,
            app_name: stringOrEmpty(notification.appName),
            app_icon: stringOrEmpty(notification.appIcon),
            desktop_entry: stringOrEmpty(notification.desktopEntry),
            summary: stringOrEmpty(notification.summary),
            body: stringOrEmpty(notification.body),
            urgency: stringOrEmpty(NotificationUrgency.toString(notification.urgency)),
            output_name: notificationTargetOutputName(),
            image: shellConfig.notificationImagesEnabled ? stringOrEmpty(notification.image) : "",
            unread: true,
            closed: false,
            closed_reason: "",
            toast_visible: !notificationDnd || stringOrEmpty(NotificationUrgency.toString(notification.urgency)).toLowerCase() === "critical",
            timeout_ms: notification.expireTimeout,
            actions: arrayOrEmpty(notification.actions).map(action => ({
                identifier: notificationActionIdentifier(action),
                text: notificationActionText(action)
            }))
        };

        replaceNotificationItem(snapshot);
    }

    function topBarTimeText() {
        if (!clock) {
            return "";
        }
        return Qt.formatDateTime(clock.date, shellConfig.topBarShowSeconds ? "ddd MMM d  h:mm:ss AP" : "ddd MMM d  h:mm AP");
    }

    function dashboardWindows() {
        const windows = [];
        const projects = arrayOrEmpty(dashboard.projects);
        for (let i = 0; i < projects.length; i += 1) {
            const projectWindows = arrayOrEmpty(projects[i] && projects[i].windows);
            for (let j = 0; j < projectWindows.length; j += 1) {
                windows.push(projectWindows[j]);
            }
        }
        return windows;
    }

    function moonlightWindowMatch(windowData) {
        if (!windowData || typeof windowData !== "object") {
            return false;
        }

        const compositorClass = stringOrEmpty(windowData.class);
        if (compositorClass === "com.moonlight_stream.moonlight") {
            return true;
        }

        const appKey = stringOrEmpty(windowData.app_key).toLowerCase();
        const appName = stringOrEmpty(windowData.app_name).toLowerCase();
        if (appKey === "moonlight" || appName === "moonlight") {
            return true;
        }

        if (compositorClass) {
            return false;
        }

        const title = stringOrEmpty(windowData.title).toLowerCase();
        return title === "moonlight"
            || title.indexOf("moonlight ") === 0
            || title.indexOf("moonlight - ") === 0;
    }

    function preferredMoonlightWindow(left, right) {
        if (!left) {
            return right || null;
        }
        if (!right) {
            return left;
        }

        const leftFocused = windowIsFocused(left);
        const rightFocused = windowIsFocused(right);
        if (leftFocused !== rightFocused) {
            return leftFocused ? left : right;
        }

        const leftFullscreen = boolOrFalse(left.fullscreen);
        const rightFullscreen = boolOrFalse(right.fullscreen);
        if (leftFullscreen !== rightFullscreen) {
            return leftFullscreen ? left : right;
        }

        const leftHidden = boolOrFalse(left.hidden);
        const rightHidden = boolOrFalse(right.hidden);
        if (leftHidden !== rightHidden) {
            return leftHidden ? right : left;
        }

        return left;
    }

    function moonlightStatus() {
        const windows = dashboardWindows().filter(windowData => moonlightWindowMatch(windowData));
        let activeWindow = null;
        for (let i = 0; i < windows.length; i += 1) {
            activeWindow = preferredMoonlightWindow(activeWindow, windows[i]);
        }

        const focused = windowIsFocused(activeWindow);
        const fullscreen = boolOrFalse(activeWindow && activeWindow.fullscreen);
        return {
            present: windows.length > 0,
            focused: focused,
            fullscreen: fullscreen,
            captureInferred: focused && fullscreen,
            workspace: stringOrEmpty(activeWindow && activeWindow.workspace),
            output: stringOrEmpty(activeWindow && activeWindow.output),
            title: stringOrEmpty(activeWindow && activeWindow.title),
            windowCount: windows.length
        };
    }

    function neutralChipFill(hovered) {
        return colors.cardAlt;
    }

    function neutralChipBorder(hovered) {
        return hovered ? colors.blueMuted : colors.border;
    }

    function neutralChipText(hovered) {
        return colors.text;
    }

    function stateChipFill(active, hovered, activeFill) {
        return active ? activeFill : colors.cardAlt;
    }

    function stateChipBorder(active, hovered, activeBorder) {
        return active ? activeBorder : neutralChipBorder(hovered);
    }

    function stateChipText(active, hovered, activeText) {
        return active ? activeText : neutralChipText(hovered);
    }

    function workspaceNameValue(workspace) {
        if (typeof workspace === "string" || typeof workspace === "number") {
            return stringOrEmpty(workspace);
        }
        return stringOrEmpty(workspace && (workspace.name || workspace.number || workspace.num));
    }

    function workspaceIsFocused(workspace) {
        const workspaceName = workspaceNameValue(workspace);
        const pendingWorkspaceFocus = pendingFocusIntentFor("workspace_focus");
        if (pendingWorkspaceFocus) {
            return pendingFocusIntentMatches("workspace_focus", workspaceName);
        }
        const currentWorkspace = stringOrEmpty(dashboardFocusState().current_workspace_name);
        return workspaceName !== "" && currentWorkspace !== "" && workspaceName === currentWorkspace;
    }

    function audioNode() {
        return Pipewire.ready ? Pipewire.defaultAudioSink : null;
    }

    function audioSourceNode() {
        return Pipewire.ready ? Pipewire.defaultAudioSource : null;
    }

    function audioNodes() {
        const nodes = arrayOrEmpty(Pipewire.nodes ? Pipewire.nodes.values : []);
        const sinks = [];
        for (let i = 0; i < nodes.length; i += 1) {
            const node = nodes[i];
            if (!(node && node.ready && boolOrFalse(node.isSink) && node.audio)) {
                continue;
            }
            sinks.push(node);
        }
        return sinks;
    }

    function audioSourceNodes() {
        const nodes = arrayOrEmpty(Pipewire.nodes ? Pipewire.nodes.values : []);
        const sources = [];
        for (let i = 0; i < nodes.length; i += 1) {
            const node = nodes[i];
            if (!(node && node.ready && !boolOrFalse(node.isSink) && node.audio)) {
                continue;
            }
            sources.push(node);
        }
        return sources;
    }

    function audioSinkIdentity(node) {
        return stringOrEmpty(node && (node.objectSerial || node.id || node.name || node.nickname || node.description));
    }

    function audioSourceIdentity(node) {
        return stringOrEmpty(node && (node.objectSerial || node.id || node.name || node.nickname || node.description));
    }

    function audioSinkLabel(node) {
        let s = stringOrEmpty(node && (node.description || node.nickname || node.name));
        if (!s) {
            return "Audio output";
        }
        // Drop the controller prefix shared by every internal output (e.g.
        // "Meteor Lake-P HD Audio Controller HDMI / DisplayPort 3 Output") and the
        // trailing " Output" so the meaningful part is readable in a narrow row.
        s = s.replace(/^.*HD Audio Controller\s+/, "");
        s = s.replace(/\s+Output$/, "");
        return s || "Audio output";
    }

    // Friendly category for an output, shown as a secondary tag so the otherwise
    // cryptic "HDMI / DisplayPort N" entries (and which port is a TV/monitor) are
    // identifiable at a glance.
    function audioSinkKind(node) {
        const name = stringOrEmpty(node && node.name).toLowerCase();
        const hay = (name + " " + stringOrEmpty(node && node.description)).toLowerCase();
        if (name.indexOf("bluez") === 0 || hay.indexOf("bluetooth") >= 0) {
            return "Bluetooth";
        }
        if (hay.indexOf("hdmi") >= 0 || hay.indexOf("displayport") >= 0) {
            return "TV / external display";
        }
        if (hay.indexOf("dock") >= 0) {
            return "USB-C dock";
        }
        if (hay.indexOf("headphone") >= 0) {
            return "Headphones";
        }
        if (hay.indexOf("usb") >= 0) {
            return "USB audio";
        }
        if (hay.indexOf("analog") >= 0 || hay.indexOf("speaker") >= 0) {
            return "Built-in speakers";
        }
        return "";
    }

    function audioSourceLabel(node) {
        return stringOrEmpty(node && (node.description || node.nickname || node.name || "Audio input"));
    }

    function audioSinkIsActive(node) {
        return audioSinkIdentity(node) === audioSinkIdentity(audioNode());
    }

    function audioSourceIsActive(node) {
        return audioSourceIdentity(node) === audioSourceIdentity(audioSourceNode());
    }

    function audioReady() {
        const node = audioNode();
        return !!(node && node.ready && node.audio);
    }

    function audioInputReady() {
        const node = audioSourceNode();
        return !!(node && node.ready && node.audio);
    }

    function volumePercent() {
        const node = audioNode();
        if (!(node && node.audio)) {
            return 0;
        }
        return Math.round(Math.max(0, Number(node.audio.volume || 0)) * 100);
    }

    function inputVolumePercent() {
        const node = audioSourceNode();
        if (!(node && node.audio)) {
            return 0;
        }
        return Math.round(Math.max(0, Number(node.audio.volume || 0)) * 100);
    }

    function audioLabel() {
        if (!audioReady()) {
            return "Audio --";
        }
        const node = audioNode();
        if (boolOrFalse(node.audio.muted) || volumePercent() === 0) {
            return "Muted";
        }
        return "Vol " + String(volumePercent()) + "%";
    }

    function audioDetail() {
        const node = audioNode();
        if (!(node && node.ready)) {
            return "PipeWire unavailable";
        }
        return audioSinkLabel(node);
    }

    function audioInputDetail() {
        const node = audioSourceNode();
        if (!(node && node.ready)) {
            return "Input unavailable";
        }
        return audioSourceLabel(node);
    }

    function changeVolume(delta) {
        const node = audioNode();
        if (!(node && node.audio)) {
            return;
        }

        const current = Math.max(0, Number(node.audio.volume || 0));
        node.audio.volume = Math.max(0, Math.min(1.5, current + delta));
    }

    function setInputVolumePercent(percent) {
        const node = audioSourceNode();
        if (!(node && node.audio)) {
            return;
        }
        node.audio.volume = Math.max(0, Math.min(1.5, Number(percent || 0) / 100));
    }

    function toggleMute() {
        const node = audioNode();
        if (!(node && node.audio)) {
            return;
        }
        node.audio.muted = !boolOrFalse(node.audio.muted);
    }

    function toggleInputMute() {
        const node = audioSourceNode();
        if (!(node && node.audio)) {
            return;
        }
        node.audio.muted = !boolOrFalse(node.audio.muted);
    }

    function setPreferredAudioSink(node) {
        if (!(Pipewire.ready && node && node.ready)) {
            return;
        }
        Pipewire.preferredDefaultAudioSink = node;
        const name = stringOrEmpty(node.name);
        if (name) {
            const value = "{\"name\":\"" + name + "\"}";
            // Pin BOTH the configured (persistent preference) AND the active default
            // to the chosen real sink. Setting only the active sink is not enough:
            // if the CONFIGURED default points at a stale/transient node — e.g. the
            // voxtype dictation tool leaves a "...voxtype-wrapped" sink that no
            // longer exists — WirePlumber can't honor it and reverts the active sink
            // to the highest-priority device (the USB-C dock), so the click "doesn't
            // hold". Forcing configured to a valid sink makes the selection stick.
            runDetached(["pw-metadata", "0", "default.configured.audio.sink", value]);
            runDetached(["pw-metadata", "0", "default.audio.sink", value]);
        }
    }

    function setPreferredAudioSource(node) {
        if (!(Pipewire.ready && node && node.ready)) {
            return;
        }
        Pipewire.preferredDefaultAudioSource = node;
    }

    function audioInputMuted() {
        return boolOrFalse(audioSourceNode() && audioSourceNode().audio && audioSourceNode().audio.muted);
    }

    function brightnessTargetState(target) {
        const key = stringOrEmpty(target);
        if (key === "keyboard") {
            return brightnessState.keyboard || {
                available: false,
                label: "Keyboard backlight",
                device: "",
                percent: 0,
                current: 0,
                max: 0
            };
        }
        return brightnessState.display || {
            available: false,
            label: "Display brightness",
            device: "",
            percent: 0,
            current: 0,
            max: 0
        };
    }

    function brightnessAvailable(target) {
        return boolOrFalse(brightnessTargetState(target).available);
    }

    function brightnessPercent(target) {
        return Math.max(0, Math.min(100, Number(brightnessTargetState(target).percent || 0)));
    }

    function brightnessLabel(target) {
        return stringOrEmpty(brightnessTargetState(target).label || "Brightness");
    }

    function brightnessDeviceLabel(target) {
        const device = stringOrEmpty(brightnessTargetState(target).device);
        return device ? device : "Unavailable";
    }

    function brightnessDetail(target) {
        const state = brightnessTargetState(target);
        if (!boolOrFalse(state.available)) {
            return brightnessLabel(target) + " unavailable on this host";
        }
        return brightnessDeviceLabel(target) + "  •  " + String(brightnessPercent(target)) + "%";
    }

    function beginBrightnessAction(target, percent) {
        brightnessActionTarget = target;
        brightnessActionStdout = "";
        brightnessActionStderr = "";
        brightnessActionError = "";
        brightnessActionProcess.command = [shellConfig.brightnessActionBin, "set", target, String(percent)];
        brightnessActionProcess.running = true;
    }

    function finishBrightnessAction() {
        const errorMessage = stringOrEmpty(brightnessActionStderr).trim();
        if (errorMessage) {
            brightnessActionError = errorMessage;
        }
        brightnessActionTarget = "";
        brightnessActionStdout = "";
        brightnessActionStderr = "";
        const queuedTarget = stringOrEmpty(brightnessQueuedTarget);
        const queuedPercent = Number(brightnessQueuedPercent);
        brightnessQueuedTarget = "";
        brightnessQueuedPercent = -1;
        if (queuedTarget && queuedPercent >= 0 && brightnessAvailable(queuedTarget) && brightnessActionProcess && !brightnessActionProcess.running) {
            beginBrightnessAction(queuedTarget, Math.max(0, Math.min(100, Math.round(queuedPercent))));
        }
    }

    function setBrightness(target, percent) {
        const normalizedTarget = stringOrEmpty(target);
        if (!brightnessAvailable(normalizedTarget)) {
            return;
        }

        const nextPercent = Math.max(0, Math.min(100, Math.round(Number(percent || 0))));
        if (!brightnessActionProcess) {
            return;
        }
        if (brightnessActionProcess.running) {
            brightnessQueuedTarget = normalizedTarget;
            brightnessQueuedPercent = nextPercent;
            return;
        }
        beginBrightnessAction(normalizedTarget, nextPercent);
    }

    function defaultBluetoothAdapter() {
        return Bluetooth.defaultAdapter || null;
    }

    function bluetoothAvailable() {
        return !!defaultBluetoothAdapter();
    }

    function bluetoothEnabled() {
        const adapter = defaultBluetoothAdapter();
        return !!(adapter && adapter.enabled);
    }

    function bluetoothDevices() {
        const adapter = defaultBluetoothAdapter();
        if (!adapter) {
            return [];
        }
        const devices = adapter.devices;
        return arrayOrEmpty(devices && devices.values ? devices.values : devices);
    }

    function bluetoothConnectedDevices() {
        const devices = bluetoothDevices();
        const connected = [];
        for (let i = 0; i < devices.length; i += 1) {
            if (boolOrFalse(devices[i] && devices[i].connected)) {
                connected.push(devices[i]);
            }
        }
        return connected;
    }

    function bluetoothConnectedCount() {
        return bluetoothConnectedDevices().length;
    }

    function bluetoothLabel() {
        if (!bluetoothAvailable()) {
            return "BT --";
        }
        if (!bluetoothEnabled()) {
            return "BT Off";
        }
        const connected = bluetoothConnectedCount();
        if (connected > 0) {
            return "BT " + String(connected);
        }
        return "BT On";
    }

    function bluetoothDetail() {
        if (!bluetoothAvailable()) {
            return "No Bluetooth adapter";
        }
        if (!bluetoothEnabled()) {
            return "Bluetooth disabled";
        }
        const connected = bluetoothConnectedDevices();
        if (!connected.length) {
            return "Bluetooth enabled";
        }
        const names = [];
        for (let i = 0; i < connected.length; i += 1) {
            names.push(stringOrEmpty(connected[i] && connected[i].name) || "Connected device");
        }
        return names.join(" • ");
    }

    function setBluetoothEnabled(enabled) {
        const adapter = defaultBluetoothAdapter();
        if (!adapter) {
            return;
        }
        adapter.enabled = enabled;
    }

    function toggleBluetoothEnabled() {
        setBluetoothEnabled(!bluetoothEnabled());
    }

    function toggleBluetoothDevice(device) {
        if (!device) {
            return;
        }
        if (boolOrFalse(device.connected)) {
            device.disconnect();
            return;
        }
        device.connect();
    }

    function batteryDevice() {
        return UPower.displayDevice;
    }

    function batteryReady() {
        const device = batteryDevice();
        return !!(device && device.ready && device.isPresent && device.isLaptopBattery);
    }

    function batteryDurationCompact(seconds) {
        const totalSeconds = Math.max(0, Math.round(Number(seconds || 0)));
        if (totalSeconds <= 0) {
            return "";
        }

        const totalMinutes = Math.round(totalSeconds / 60);
        if (totalMinutes < 60) {
            return String(totalMinutes) + "m";
        }

        const hours = Math.floor(totalMinutes / 60);
        const minutes = totalMinutes % 60;
        if (minutes <= 0) {
            return String(hours) + "h";
        }
        return String(hours) + "h " + String(minutes) + "m";
    }

    function batteryDurationLabel() {
        const device = batteryDevice();
        if (!batteryReady()) {
            return "";
        }

        if (device.state === UPowerDeviceState.Charging && Number(device.timeToFull || 0) > 0) {
            return batteryDurationCompact(device.timeToFull) + " to full";
        }
        if (device.state === UPowerDeviceState.Discharging && Number(device.timeToEmpty || 0) > 0) {
            return batteryDurationCompact(device.timeToEmpty) + " left";
        }
        return "";
    }

    function batteryStateText() {
        const device = batteryDevice();
        if (!batteryReady()) {
            return "";
        }
        if (device.state === UPowerDeviceState.Charging) {
            return "Charging";
        }
        if (device.state === UPowerDeviceState.Discharging) {
            return "Discharging";
        }
        if (device.state === UPowerDeviceState.FullyCharged) {
            return "Fully charged";
        }
        if (device.state === UPowerDeviceState.PendingCharge) {
            return "Pending charge";
        }
        if (device.state === UPowerDeviceState.PendingDischarge) {
            return "Pending discharge";
        }
        if (device.state === UPowerDeviceState.Empty) {
            return "Empty";
        }
        return "Battery";
    }

    function batteryPercentNumber() {
        const device = batteryDevice();
        if (!batteryReady()) {
            return 0;
        }

        let percentage = Number(device.percentage || 0);
        if (percentage > 0 && percentage <= 1.5) {
            percentage *= 100;
        }
        return Math.round(Math.max(0, percentage));
    }

    function batteryLabel() {
        const device = batteryDevice();
        if (!batteryReady()) {
            return "";
        }

        const percentage = batteryPercentNumber();
        const duration = batteryDurationLabel();
        if (device.state === UPowerDeviceState.Charging) {
            return duration ? "Charging " + String(percentage) + "% · " + duration : "Charging " + String(percentage) + "%";
        }
        if (device.state === UPowerDeviceState.FullyCharged) {
            return "Full " + String(percentage) + "%";
        }
        return duration ? "Battery " + String(percentage) + "% · " + duration : "Battery " + String(percentage) + "%";
    }

    function batteryPercentValue() {
        return batteryPercentNumber();
    }

    function batteryIsDischarging() {
        const device = batteryDevice();
        return batteryReady() && device.state === UPowerDeviceState.Discharging;
    }

    function batteryCritical() {
        return batteryIsDischarging() && batteryPercentValue() <= 15;
    }

    function batteryLow() {
        return batteryIsDischarging() && batteryPercentValue() <= 30;
    }

    function batteryIconSource() {
        const device = batteryDevice();
        const iconName = stringOrEmpty(device ? device.iconName : "");
        return iconName ? Quickshell.iconPath(iconName, true) : "";
    }

    function batteryHealthLabel() {
        const device = batteryDevice();
        if (!(batteryReady() && boolOrFalse(device.healthSupported))) {
            return "";
        }
        return "Health " + String(Math.round(Math.max(0, Number(device.healthPercentage || 0)))) + "%";
    }

    function batteryRateLabel() {
        const device = batteryDevice();
        if (!batteryReady()) {
            return "";
        }
        const watts = Math.abs(Number(device.changeRate || 0));
        if (watts <= 0) {
            return "";
        }
        return Number(watts).toFixed(1) + " W";
    }

    function batteryEnergyLabel() {
        const device = batteryDevice();
        if (!batteryReady()) {
            return "";
        }
        const energy = Number(device.energy || 0);
        const capacity = Number(device.energyCapacity || 0);
        if (capacity <= 0) {
            return "";
        }
        return Number(energy).toFixed(1) + " / " + Number(capacity).toFixed(1) + " Wh";
    }

    function batteryMetadataLabel() {
        const device = batteryDevice();
        if (!batteryReady()) {
            return "";
        }
        const bits = [];
        const model = stringOrEmpty(device.model);
        const nativePath = stringOrEmpty(device.nativePath);
        if (model) {
            bits.push(model);
        }
        if (nativePath) {
            bits.push(nativePath);
        }
        return bits.join("  •  ");
    }

    function powerProfilesSupported() {
        return boolOrFalse(shellConfig.supportsPowerProfiles);
    }

    function powerProfileChoices() {
        const choices = [{
                value: PowerProfile.PowerSaver,
                label: "Power Saver"
            }, {
                value: PowerProfile.Balanced,
                label: "Balanced"
            }];
        if (powerProfilesSupported() && boolOrFalse(PowerProfiles.hasPerformanceProfile)) {
            choices.push({
                value: PowerProfile.Performance,
                label: "Performance"
            });
        }
        return choices;
    }

    function powerProfileLabel(profile) {
        if (profile === PowerProfile.PowerSaver) {
            return "Power Saver";
        }
        if (profile === PowerProfile.Performance) {
            return "Performance";
        }
        return "Balanced";
    }

    function currentPowerProfile() {
        if (!powerProfilesSupported()) {
            return PowerProfile.Balanced;
        }
        return PowerProfiles.profile;
    }

    function powerProfileIsActive(profile) {
        return currentPowerProfile() === profile;
    }

    function setPowerProfile(profile) {
        if (!powerProfilesSupported()) {
            return;
        }
        if (PowerProfiles.profile === profile) {
            return;
        }
        PowerProfiles.profile = profile;
    }

    function powerProfileDegradationText() {
        if (!powerProfilesSupported()) {
            return "";
        }
        if (PowerProfiles.degradationReason === PerformanceDegradationReason.LapDetected) {
            return "Performance mode limited: lap detected";
        }
        if (PowerProfiles.degradationReason === PerformanceDegradationReason.HighTemperature) {
            return "Performance mode limited: high temperature";
        }
        return "";
    }

    function powerProfileHoldText() {
        if (!powerProfilesSupported()) {
            return "";
        }
        const holds = arrayOrEmpty(PowerProfiles.holds);
        if (!holds.length) {
            return "";
        }
        const labels = [];
        for (let i = 0; i < holds.length; i += 1) {
            const hold = holds[i];
            const applicationId = stringOrEmpty(hold && hold.applicationId);
            const reason = stringOrEmpty(hold && hold.reason);
            const bits = [];
            if (applicationId) {
                bits.push(applicationId);
            }
            if (reason) {
                bits.push(reason);
            }
            if (bits.length) {
                labels.push(bits.join(": "));
            }
        }
        if (!labels.length) {
            return "";
        }
        return "Profile holds: " + labels.join("  •  ");
    }

    function hasBrightnessOrPowerControls() {
        return brightnessAvailable("display")
            || brightnessAvailable("keyboard")
            || batteryReady()
            || powerProfilesSupported();
    }

    function brightnessPowerSummaryText() {
        const bits = [];
        if (brightnessAvailable("display")) {
            bits.push("Display " + String(brightnessPercent("display")) + "%");
        }
        if (brightnessAvailable("keyboard")) {
            bits.push("Keyboard " + String(brightnessPercent("keyboard")) + "%");
        }
        if (batteryReady()) {
            bits.push(batteryStateText() + " " + String(batteryPercentNumber()) + "%");
        }
        if (powerProfilesSupported()) {
            bits.push(powerProfileLabel(currentPowerProfile()));
        }
        return bits.join("  •  ");
    }

    function lidPolicySupported() {
        return boolOrFalse(shellConfig.supportsLidPolicyControls)
            && boolOrFalse(lidPolicyState.supported || shellConfig.supportsLidPolicyControls);
    }

    function lidPolicyChoices() {
        return [{
                value: "ignore",
                label: "Ignore"
            }, {
                value: "lock",
                label: "Lock"
            }, {
                value: "suspend",
                label: "Suspend"
            }, {
                value: "hibernate",
                label: "Hibernate"
            }, {
                value: "poweroff",
                label: "Power Off"
            }];
    }

    function lidPolicyLabel(action) {
        const value = stringOrEmpty(action).toLowerCase();
        if (value === "ignore") {
            return "Keep Awake";
        }
        if (value === "poweroff") {
            return "Power Off";
        }
        if (value === "lock") {
            return "Lock";
        }
        if (value === "hibernate") {
            return "Hibernate";
        }
        return "Suspend";
    }

    function syncLidPolicyDraft(force) {
        if (!lidPolicySupported()) {
            return;
        }
        if (lidPolicyDraftDirty && !force) {
            return;
        }
        lidPolicyDraftBattery = stringOrEmpty(lidPolicyState.battery || "suspend") || "suspend";
        lidPolicyDraftExternalPower = stringOrEmpty(lidPolicyState.externalPower || "lock") || "lock";
        lidPolicyDraftDocked = stringOrEmpty(lidPolicyState.docked || "ignore") || "ignore";
        lidPolicyDraftDirty = false;
    }

    function resetLidPolicyDraft() {
        lidPolicyApplyError = "";
        syncLidPolicyDraft(true);
    }

    function lidPolicyDraftValue(kind) {
        const normalized = stringOrEmpty(kind);
        if (normalized === "externalPower") {
            return stringOrEmpty(lidPolicyDraftExternalPower || "lock") || "lock";
        }
        if (normalized === "docked") {
            return stringOrEmpty(lidPolicyDraftDocked || "ignore") || "ignore";
        }
        return stringOrEmpty(lidPolicyDraftBattery || "suspend") || "suspend";
    }

    function setLidPolicyDraft(kind, value) {
        const normalizedKind = stringOrEmpty(kind);
        const normalizedValue = stringOrEmpty(value).toLowerCase();
        if (!normalizedKind || !normalizedValue) {
            return;
        }
        if (normalizedKind === "externalPower") {
            lidPolicyDraftExternalPower = normalizedValue;
        } else if (normalizedKind === "docked") {
            lidPolicyDraftDocked = normalizedValue;
        } else {
            lidPolicyDraftBattery = normalizedValue;
        }
        lidPolicyDraftDirty = lidPolicyDraftBattery !== stringOrEmpty(lidPolicyState.battery || "suspend")
            || lidPolicyDraftExternalPower !== stringOrEmpty(lidPolicyState.externalPower || "lock")
            || lidPolicyDraftDocked !== stringOrEmpty(lidPolicyState.docked || "ignore");
        lidPolicyApplyError = "";
    }

    function lidPolicyPresetKeepAwakeActive() {
        return lidPolicyDraftValue("battery") === "ignore"
            && lidPolicyDraftValue("externalPower") === "ignore"
            && lidPolicyDraftValue("docked") === "ignore";
    }

    function applyKeepAwakePreset() {
        setLidPolicyDraft("battery", "ignore");
        setLidPolicyDraft("externalPower", "ignore");
        setLidPolicyDraft("docked", "ignore");
    }

    function lidPolicyApplyPending() {
        return !!(lidPolicyApplyProcess && lidPolicyApplyProcess.running);
    }

    function lidInhibitPending() {
        return !!(lidInhibitActionProcess && lidInhibitActionProcess.running);
    }

    function lidInhibitActive() {
        return boolOrFalse(lidPolicyState.inhibitActive);
    }

    function lidPolicyControlsBusy() {
        return lidPolicyApplyPending() || lidInhibitPending();
    }

    function lidPolicyExternalDisplayActive() {
        const outputs = activeDisplayOutputNames();
        for (let index = 0; index < outputs.length; index += 1) {
            if (stringOrEmpty(outputs[index]) !== "eDP-1") {
                return true;
            }
        }
        return false;
    }

    function lidPolicyEnvironmentText() {
        return lidPolicyExternalDisplayActive() ? "External display active" : "Laptop only";
    }

    function lidPolicyStatusText() {
        if (!lidPolicySupported()) {
            return "Lid-close controls are only exposed on the ThinkPad host.";
        }
        if (lidPolicyApplyPending()) {
            return "Updating ThinkPad lid policy and rebuilding the active system...";
        }
        if (lidInhibitPending()) {
            return lidInhibitActionMode === "disable"
                ? "Disabling temporary keep-awake override..."
                : "Enabling temporary keep-awake override...";
        }
        if (lidPolicyApplyError) {
            return lidPolicyApplyError;
        }
        if (lidInhibitActionError) {
            return lidInhibitActionError;
        }
        const bits = [
            "Battery " + lidPolicyLabel(lidPolicyState.battery),
            "AC " + lidPolicyLabel(lidPolicyState.externalPower),
            "Docked " + lidPolicyLabel(lidPolicyState.docked),
        ];
        if (lidInhibitActive()) {
            bits.push("Temporary override active");
        }
        bits.push(lidPolicyEnvironmentText());
        return bits.join("  •  ");
    }

    function applyLidPolicyDraft() {
        if (!lidPolicySupported() || !lidPolicyApplyProcess || lidPolicyApplyProcess.running) {
            return;
        }
        lidPolicyApplyStdout = "";
        lidPolicyApplyStderr = "";
        lidPolicyApplyError = "";
        lidInhibitActionError = "";
        lidPolicyApplyProcess.command = [
            shellConfig.pkexecBin,
            shellConfig.lidPolicyApplyBin,
            "apply",
            lidPolicyDraftValue("battery"),
            lidPolicyDraftValue("externalPower"),
            lidPolicyDraftValue("docked")
        ];
        lidPolicyApplyProcess.running = true;
    }

    function finishLidPolicyApply() {
        const raw = stringOrEmpty(lidPolicyApplyStdout).trim();
        const error = stringOrEmpty(lidPolicyApplyStderr).trim();
        let parsed = false;
        if (raw) {
            parseLidPolicy(raw);
            parsed = raw.indexOf("{") === 0;
        }
        lidPolicyApplyStdout = "";
        lidPolicyApplyStderr = "";
        lidPolicyApplyError = parsed ? "" : error;
        if (parsed) {
            syncLidPolicyDraft(true);
        }
    }

    function toggleTemporaryLidInhibit() {
        if (!lidPolicySupported() || !lidInhibitActionProcess || lidInhibitActionProcess.running) {
            return;
        }
        lidInhibitActionMode = lidInhibitActive() ? "disable" : "enable";
        lidInhibitActionStdout = "";
        lidInhibitActionStderr = "";
        lidInhibitActionError = "";
        lidInhibitActionProcess.command = [shellConfig.lidInhibitBin, lidInhibitActionMode];
        lidInhibitActionProcess.running = true;
    }

    function finishLidInhibitAction() {
        const raw = stringOrEmpty(lidInhibitActionStdout).trim();
        const error = stringOrEmpty(lidInhibitActionStderr).trim();
        const parsed = raw && raw.indexOf("{") === 0;
        if (raw) {
            parseLidPolicy(raw);
        }
        lidInhibitActionStdout = "";
        lidInhibitActionStderr = "";
        lidInhibitActionError = parsed ? "" : error;
        lidInhibitActionMode = "";
    }

    function networkLabel() {
        if (!boolOrFalse(networkState.connected)) {
            return "Offline";
        }
        if (stringOrEmpty(networkState.kind) === "wifi" && networkState.signal !== null && networkState.signal !== undefined) {
            return "Wi-Fi " + String(networkState.signal) + "%";
        }
        if (stringOrEmpty(networkState.kind) === "ethernet") {
            return "Ethernet";
        }
        return stringOrEmpty(networkState.label || "Connected");
    }

    function networkDetail() {
        if (!boolOrFalse(networkState.connected)) {
            return "No active NetworkManager connection";
        }
        return stringOrEmpty(networkState.label || "Connected");
    }

    function networkChipText(hovered) {
        if (!boolOrFalse(networkState.connected)) {
            return hovered ? colors.amber : colors.subtle;
        }
        return neutralChipText(hovered);
    }

    function systemStatsMemoryPercentValue() {
        return Math.round(Math.max(0, Number(systemStatsState.memory_percent || 0)));
    }

    function systemStatsMemoryLabel() {
        return "Mem " + String(systemStatsMemoryPercentValue()) + "%";
    }

    function systemStatsDiskPercentValue() {
        return Math.round(Math.max(0, Number(systemStatsState.disk_percent || 0)));
    }

    function systemStatsDiskLabel() {
        return "Disk " + String(systemStatsDiskPercentValue()) + "%";
    }

    function systemStatsDiskTooltip() {
        return String(Number(systemStatsState.disk_used_gb || 0).toFixed(0)) + " / " + String(Number(systemStatsState.disk_total_gb || 0).toFixed(0)) + " GB";
    }

    function diskChipFill(hovered) {
        var pct = systemStatsDiskPercentValue();
        if (pct >= 90) return hovered ? Qt.lighter(colors.red, 1.15) : Qt.rgba(colors.red.r, colors.red.g, colors.red.b, 0.15);
        if (pct >= 75) return hovered ? Qt.lighter(colors.amber, 1.15) : Qt.rgba(colors.amber.r, colors.amber.g, colors.amber.b, 0.15);
        return neutralChipFill(hovered);
    }

    function diskChipBorder(hovered) {
        var pct = systemStatsDiskPercentValue();
        if (pct >= 90) return colors.red;
        if (pct >= 75) return colors.amber;
        return neutralChipBorder(hovered);
    }

    function diskChipText(hovered) {
        var pct = systemStatsDiskPercentValue();
        if (pct >= 90) return colors.red;
        if (pct >= 75) return colors.amber;
        return neutralChipText(hovered);
    }

    function systemGenerationLabel() {
        var gen = Number(systemStatsState.system_generation || 0);
        return gen > 0 ? ("Gen " + String(gen)) : "Gen ?";
    }

    function systemStatsSummaryLabel() {
        const bits = ["Mem " + String(systemStatsMemoryPercentValue()) + "%", "Load " + String(Number(systemStatsState.load1 || 0).toFixed(2))];
        if (systemStatsState.temperature_c !== null && systemStatsState.temperature_c !== undefined) {
            bits.push(String(systemStatsState.temperature_c) + "°C");
        }
        return bits.join(" • ");
    }

    function notificationChipFill(hovered) {
        const dnd = boolOrFalse(notificationState.dnd);
        const visible = boolOrFalse(notificationState.visible);
        if (dnd) {
            return stateChipFill(true, hovered, colors.amberBg);
        }
        if (visible) {
            return stateChipFill(true, hovered, colors.blueBg);
        }
        return neutralChipFill(hovered);
    }

    function notificationChipBorder(hovered) {
        const dnd = boolOrFalse(notificationState.dnd);
        const visible = boolOrFalse(notificationState.visible);
        const unread = boolOrFalse(notificationState.has_unread);
        if (dnd) {
            return stateChipBorder(true, hovered, colors.amber);
        }
        if (visible) {
            return stateChipBorder(true, hovered, colors.blue);
        }
        if (unread) {
            return colors.blue;
        }
        return neutralChipBorder(hovered);
    }

    function notificationChipText(hovered) {
        const dnd = boolOrFalse(notificationState.dnd);
        const visible = boolOrFalse(notificationState.visible);
        if (dnd) {
            return stateChipText(true, hovered, colors.amber);
        }
        if (visible) {
            return stateChipText(true, hovered, colors.blue);
        }
        return neutralChipText(hovered);
    }

    function audioMuted() {
        return boolOrFalse(audioNode() && audioNode().audio && audioNode().audio.muted);
    }

    function audioChipBorder(hovered) {
        if (audioMuted()) {
            return colors.red;
        }
        return neutralChipBorder(hovered);
    }

    function audioChipText(hovered) {
        if (audioMuted()) {
            return colors.red;
        }
        return neutralChipText(hovered);
    }

    function batteryChipBorder(hovered) {
        if (batteryCritical()) {
            return colors.red;
        }
        if (batteryLow()) {
            return colors.amber;
        }
        return neutralChipBorder(hovered);
    }

    function batteryChipText(hovered) {
        if (batteryCritical()) {
            return colors.red;
        }
        if (batteryLow()) {
            return colors.amber;
        }
        return neutralChipText(hovered);
    }

    function powerChipFill(hovered) {
        return root.powerMenuVisible ? colors.redBg : neutralChipFill(hovered);
    }

    function powerChipBorder(hovered) {
        return root.powerMenuVisible ? colors.red : neutralChipBorder(hovered);
    }

    function powerChipText(hovered) {
        return root.powerMenuVisible ? colors.red : neutralChipText(hovered);
    }

    function notificationLabel() {
        if (boolOrFalse(notificationState.dnd)) {
            return "DND";
        }
        if (boolOrFalse(notificationState.has_unread)) {
            return "Notif " + stringOrEmpty(notificationState.display_count || "0");
        }
        return "Notif";
    }

function normalizeLauncherMode(mode) {
        const value = stringOrEmpty(mode).toLowerCase();
        const modes = arrayOrEmpty(launcherModesModel);
        for (let index = 0; index < modes.length; index += 1) {
            const candidate = stringOrEmpty(modes[index] && modes[index].id);
            if (candidate === value) {
                return candidate;
            }
        }
        return modes.length ? stringOrEmpty(modes[0] && modes[0].id) : "apps";
    }

    function launcherModeOrder() {
        return arrayOrEmpty(launcherModesModel).map(function (mode) {
            return stringOrEmpty(mode && mode.id);
        }).filter(function (mode) {
            return mode !== "";
        });
    }

    function setLauncherMode(mode) {
        launcherMode = normalizeLauncherMode(mode);
    }

    function showLauncher(mode, query) {
        settingsVisible = false;
        if (!launcherVisible) {
            launcherVisible = true;
        }

        const nextMode = normalizeLauncherMode(mode);
        const nextQuery = stringOrEmpty(query);

        if (launcherMode !== nextMode) {
            launcherMode = nextMode;
        }
        if (launcherQuery !== nextQuery) {
            launcherQuery = nextQuery;
        }

        launcherQueryDebounce.stop();
        restartLauncherQuery();
        launcherFocusTimer.restart();
    }

    function toggleLauncher() {
        if (launcherVisible) {
            closeLauncher();
            return;
        }
        showLauncher("apps", "");
    }

    function cycleLauncherMode(delta) {
        const modes = launcherModeOrder();
        if (!modes.length) {
            return;
        }

        const current = normalizeLauncherMode(launcherMode);
        const currentIndex = modes.indexOf(current);
        const startIndex = currentIndex >= 0 ? currentIndex : 0;
        const nextIndex = (startIndex + delta + modes.length) % modes.length;
        setLauncherMode(modes[nextIndex]);
    }

    function launcherTitle() {
        const meta = launcherModeMeta(launcherMode);
        return stringOrEmpty(meta && meta.title) || "Launch App";
    }

    function launcherPlaceholderText() {
        const meta = launcherModeMeta(launcherMode);
        return stringOrEmpty(meta && meta.placeholder) || "Search apps";
    }

    function launcherHelpText() {
        const meta = launcherModeMeta(launcherMode);
        return stringOrEmpty(meta && meta.help) || "Tab modes  •  Up/Down results";
    }

    function normalizeLauncherAppFilter(filterName) {
        const meta = launcherAppFilterMeta(filterName);
        return stringOrEmpty(meta && meta.id) || "all";
    }

    function setLauncherAppFilter(filterName) {
        launcherAppFilter = normalizeLauncherAppFilter(filterName);
    }

    function launcherActiveAppFilterLabel() {
        const meta = launcherAppFilterMeta(launcherAppFilter);
        return stringOrEmpty(meta && meta.label);
    }

    function launcherStatusText() {
        if (launcherLoading) {
            if (launcherMode === "files") {
                return "Searching files";
            }
            if (launcherMode === "urls") {
                return "Loading Chrome URLs";
            }
            if (launcherMode === "onepassword") {
                return "Loading 1Password items";
            }
            if (launcherMode === "clipboard") {
                return "Loading clipboard history";
            }
            if (launcherMode === "runner") {
                return "Preparing command";
            }
            if (launcherMode === "snippets") {
                return "Loading curated commands";
            }
            if (launcherMode === "apps") {
                return "Searching apps";
            }
            return "Searching with Elephant";
        }
        if (launcherMode === "files") {
            return launcherEntries.length ? launcherEntries.length + " file result" + (launcherEntries.length === 1 ? "" : "s") : "No matching files";
        }
        if (launcherMode === "urls") {
            return launcherEntries.length ? launcherEntries.length + " URL result" + (launcherEntries.length === 1 ? "" : "s") : "No matching URLs";
        }
        if (launcherMode === "runner") {
            return launcherEntries.length ? launcherEntries.length + " command ready" : "Type a command to run";
        }
        if (launcherMode === "snippets") {
            return launcherEntries.length ? launcherEntries.length + " curated command" + (launcherEntries.length === 1 ? "" : "s") : "No matching curated commands";
        }
        if (launcherMode === "sessions") {
            return launcherEntries.length ? launcherEntries.length + " AI session" + (launcherEntries.length === 1 ? "" : "s") : "No matching AI sessions";
        }
        if (launcherMode === "windows") {
            return launcherEntries.length ? launcherEntries.length + " window" + (launcherEntries.length === 1 ? "" : "s") : "No matching windows";
        }
        if (launcherMode === "onepassword") {
            return launcherEntries.length ? launcherEntries.length + " 1Password item" + (launcherEntries.length === 1 ? "" : "s") : "No matching 1Password items";
        }
        if (launcherMode === "clipboard") {
            return launcherEntries.length ? launcherEntries.length + " clipboard item" + (launcherEntries.length === 1 ? "" : "s") : "No matching clipboard items";
        }
        const appCountLabel = launcherEntries.length
            ? launcherEntries.length + " app" + (launcherEntries.length === 1 ? "" : "s")
            : "No matching apps";
        if (launcherMode === "apps" && launcherAppFilter !== "all") {
            return appCountLabel + "  •  " + launcherActiveAppFilterLabel();
        }
        return appCountLabel;
    }

    function launcherEmptyText() {
        if (launcherError) {
            return launcherError;
        }
        if (launcherMode === "files") {
            return "No files match the current query";
        }
        if (launcherMode === "urls") {
            return "No Chrome URLs or PWAs match the current query";
        }
        if (launcherMode === "runner") {
            return "Type a command to run from the current context";
        }
        if (launcherMode === "snippets") {
            return "No curated commands match the current query";
        }
        if (launcherMode === "sessions") {
            return "No AI sessions match the current query";
        }
        if (launcherMode === "windows") {
            return "No windows match the current query";
        }
        if (launcherMode === "onepassword") {
            return "No 1Password items match the current query";
        }
        if (launcherMode === "clipboard") {
            return "No clipboard items match the current query";
        }
        return "No apps match the current query";
    }

    function updateLauncherInput(rawInput) {
        let nextMode = launcherMode;
        let nextQuery = stringOrEmpty(rawInput);

        if (nextQuery === "/" || nextQuery.indexOf("/") === 0) {
            nextMode = "files";
            nextQuery = nextQuery.slice(1).replace(/^\s+/, "");
        } else if (nextQuery.indexOf(";u") === 0) {
            nextMode = "urls";
            nextQuery = nextQuery.slice(2).replace(/^\s+/, "");
        } else if (nextQuery === ">" || nextQuery.indexOf(">") === 0) {
            nextMode = "runner";
            nextQuery = nextQuery.slice(1).replace(/^\s+/, "");
        } else if (nextQuery === "$" || nextQuery.indexOf("$") === 0) {
            nextMode = "snippets";
            nextQuery = nextQuery.slice(1).replace(/^\s+/, "");
        } else if (nextQuery.indexOf(";s") === 0) {
            nextMode = "sessions";
            nextQuery = nextQuery.slice(2).replace(/^\s+/, "");
        } else if (nextQuery.indexOf(";w") === 0) {
            nextMode = "windows";
            nextQuery = nextQuery.slice(2).replace(/^\s+/, "");
        } else if (nextQuery === "*" || nextQuery.indexOf("* ") === 0) {
            nextMode = "onepassword";
            nextQuery = nextQuery.slice(1).replace(/^\s+/, "");
        } else if (nextQuery === ":" || nextQuery.indexOf(":") === 0) {
            nextMode = "clipboard";
            nextQuery = nextQuery.slice(1).replace(/^\s+/, "");
        } else if (nextQuery.indexOf(";a") === 0) {
            nextMode = "apps";
            nextQuery = nextQuery.slice(2).replace(/^\s+/, "");
        }

        if (launcherMode !== nextMode) {
            launcherMode = nextMode;
        }
        if (launcherQuery !== nextQuery) {
            launcherQuery = nextQuery;
        }
        if (launcherSessionSwitcherActive && (nextMode !== "sessions" || nextQuery !== "")) {
            launcherSessionSwitcherActive = false;
        }
        if (launcherField && launcherField.text !== nextQuery) {
            launcherNormalizingInput = true;
            launcherField.text = nextQuery;
            launcherNormalizingInput = false;
        }
    }

    function launcherQueryTokens(query) {
        const trimmed = stringOrEmpty(query).trim().toLowerCase();
        if (!trimmed) {
            return [];
        }
        return trimmed.split(/\s+/).filter(function (token) {
            return !!token;
        });
    }

    function launcherTokensMatch(tokens, haystackParts) {
        if (!tokens.length) {
            return true;
        }

        const haystack = haystackParts.join(" ").toLowerCase();
        for (let i = 0; i < tokens.length; i += 1) {
            if (haystack.indexOf(tokens[i]) === -1) {
                return false;
            }
        }
        return true;
    }

    function onePasswordCategoryLabel(category) {
        const value = stringOrEmpty(category).toLowerCase();
        if (value === "login") {
            return "Login";
        }
        if (value === "secure_note") {
            return "Note";
        }
        if (value === "ssh_key") {
            return "SSH";
        }
        if (value === "credit_card") {
            return "Card";
        }
        if (value === "identity") {
            return "Identity";
        }
        if (value === "document") {
            return "Document";
        }
        if (value === "password") {
            return "Password";
        }
        if (value === "api_credential") {
            return "API";
        }
        if (!value) {
            return "";
        }
        return value.replace(/_/g, " ");
    }

    function onePasswordEntries(query) {
        const trimmed = stringOrEmpty(query).trim().toLowerCase();
        const tokens = trimmed ? trimmed.split(/\s+/).filter(function (token) {
            return !!token;
        }) : [];

        return arrayOrEmpty(onePasswordEntriesCache).filter(function (entry) {
            if (!tokens.length) {
                return true;
            }

            const haystack = [stringOrEmpty(entry.text), stringOrEmpty(entry.subtext), stringOrEmpty(entry.category), onePasswordCategoryLabel(entry.category)].join(" ").toLowerCase();

            for (let i = 0; i < tokens.length; i += 1) {
                if (haystack.indexOf(tokens[i]) === -1) {
                    return false;
                }
            }

            return true;
        });
    }

    function launcherEntryHasState(entry, stateName) {
        const target = stringOrEmpty(stateName).toLowerCase();
        const states = arrayOrEmpty(entry && entry.state);
        for (let i = 0; i < states.length; i += 1) {
            if (stringOrEmpty(states[i]).toLowerCase() === target) {
                return true;
            }
        }
        return false;
    }

    function launcherFileIsDirectory(entry) {
        if (stringOrEmpty(entry && entry.kind) !== "file") {
            return false;
        }
        if (launcherEntryHasState(entry, "dir") || launcherEntryHasState(entry, "directory") || launcherEntryHasState(entry, "folder")) {
            return true;
        }
        const identifier = stringOrEmpty(entry && entry.identifier);
        return identifier.endsWith("/");
    }

    function clipboardEntryHasImagePreview(entry) {
        if (stringOrEmpty(entry && entry.kind) !== "clipboard") {
            return false;
        }
        const previewType = stringOrEmpty(entry && entry.preview_type).toLowerCase();
        const preview = stringOrEmpty(entry && entry.preview);
        if (previewType !== "file" || !preview) {
            return false;
        }
        if (preview.indexOf("/") === 0) {
            return /\.(png|jpe?g|webp|gif|bmp|svg)$/i.test(preview);
        }
        if (preview.indexOf("file://") === 0) {
            return /\.(png|jpe?g|webp|gif|bmp|svg)$/i.test(preview);
        }
        return false;
    }

    function clipboardImageSource(entry) {
        if (!clipboardEntryHasImagePreview(entry)) {
            return "";
        }
        const preview = stringOrEmpty(entry && entry.preview);
        if (preview.indexOf("file://") === 0) {
            return preview;
        }
        if (preview.indexOf("/") === 0) {
            return "file://" + preview;
        }
        return "";
    }

    function clipboardEntryTitle(entry) {
        const text = stringOrEmpty(entry && entry.text).trim();
        if (text) {
            return text.replace(/\s+/g, " ");
        }
        if (clipboardEntryHasImagePreview(entry)) {
            return "Image clipboard item";
        }
        return "Clipboard item";
    }

    function clipboardEntrySubtitle(entry) {
        const bits = [];
        const subtext = stringOrEmpty(entry && entry.subtext);
        if (subtext) {
            bits.push(subtext);
        }
        if (launcherEntryHasState(entry, "pinned")) {
            bits.push("Pinned");
        }
        if (clipboardEntryHasImagePreview(entry)) {
            bits.push("Image");
        }
        return bits.join("  •  ");
    }

    function activeClipboardEntry() {
        const entry = activeLauncherEntry();
        if (stringOrEmpty(entry && entry.kind) !== "clipboard") {
            return null;
        }
        return entry;
    }

    function clipboardPreviewTitle(entry) {
        return clipboardEntryTitle(entry);
    }

    function clipboardPreviewBody(entry) {
        if (!entry) {
            return "";
        }
        const previewType = stringOrEmpty(entry.preview_type).toLowerCase();
        if (previewType === "text") {
            const preview = stringOrEmpty(entry.preview);
            return preview || stringOrEmpty(entry.text);
        }
        if (previewType === "file") {
            return stringOrEmpty(entry.preview);
        }
        return stringOrEmpty(entry.preview) || stringOrEmpty(entry.text);
    }

    function emptySessionPreview() {
        return {
            status: "idle",
            kind: "status",
            session_key: "",
            preview_mode: "",
            preview_reason: "",
            is_live: false,
            is_remote: false,
            tool: "",
            project_name: "",
            host_name: "",
            connection_key: "",
            execution_mode: "",
            focus_mode: "",
            window_id: 0,
            pane_label: "",
            pane_title: "",
            surface_key: "",
            content: "",
            message: "",
            updated_at: ""
        };
    }

    function activeLauncherSessionEntry() {
        const entry = activeLauncherEntry();
        if (stringOrEmpty(entry && entry.kind) !== "session") {
            return null;
        }
        return entry;
    }

    function clearSessionPreview() {
        sessionPreviewTargetKey = "";
        sessionPreview = emptySessionPreview();
    }

    function restartSessionPreview() {
        const entry = activeLauncherSessionEntry();
        if (!launcherVisible || launcherMode !== "sessions" || !entry) {
            clearSessionPreview();
            return;
        }

        const sessionKey = stringOrEmpty(entry.session_key || entry.identifier);
        if (!sessionKey) {
            clearSessionPreview();
            return;
        }

        sessionPreviewTargetKey = sessionKey;
        const herdrSession = stringOrEmpty(entry.source) === "herdr" || stringOrEmpty(entry.pane_id);
        sessionPreview = Object.assign(emptySessionPreview(), {
            status: "focus_required",
            kind: "status",
            session_key: sessionKey,
            preview_mode: "focus_only",
            preview_reason: herdrSession ? "herdr_focus_only" : "herdr_focus_required",
            tool: toolLabel(entry),
            project_name: stringOrEmpty(entry.project_name || entry.project),
            host_name: stringOrEmpty(entry.host_name),
            connection_key: stringOrEmpty(entry.connection_key),
            execution_mode: stringOrEmpty(entry.execution_mode),
            focus_mode: stringOrEmpty(entry.focus_mode),
            window_id: Number(entry.window_id || 0),
            pane_label: sessionPaneLabel(entry),
            pane_title: stringOrEmpty(entry.pane_title),
            surface_key: stringOrEmpty(entry.surface_key),
            agent_status: stringOrEmpty(entry.agent_status),
            agent_status_state: stringOrEmpty(entry.agent_status_state),
            cwd: stringOrEmpty(entry.cwd),
            foreground_cwd: stringOrEmpty(entry.foreground_cwd),
            workspace_id: stringOrEmpty(entry.workspace_id),
            tab_id: stringOrEmpty(entry.tab_id),
            pane_id: stringOrEmpty(entry.pane_id),
            terminal_id: stringOrEmpty(entry.terminal_id),
            message: herdrSession
                ? "Focus this Herdr pane to inspect live output."
                : "Focus the corresponding Herdr pane for live inspection."
        });
    }

    function ensureSessionPreviewForSelection() {
        const entry = activeLauncherSessionEntry();
        if (!launcherVisible || launcherMode !== "sessions" || !entry) {
            clearSessionPreview();
            return;
        }

        const sessionKey = stringOrEmpty(entry.session_key || entry.identifier);
        if (!sessionKey) {
            clearSessionPreview();
            return;
        }

        if (sessionPreviewTargetKey === sessionKey && stringOrEmpty(sessionPreview.status) !== "loading") {
            return;
        }

        sessionPreviewDebounce.restart();
    }

    function sessionPreviewTitle() {
        const alias = buildSessionAlias(
            hostMonogram(
                stringOrEmpty(sessionPreview.execution_mode),
                stringOrEmpty(sessionPreview.host_name),
                stringOrEmpty(sessionPreview.connection_key)
            ),
            stringOrEmpty(sessionPreview.pane_id || sessionPreview.pane_label)
        );
        if (alias.length > 0) {
            return alias;
        }
        const entry = activeLauncherSessionEntry();
        return entry ? sessionPrimaryLabel(entry) : "Session Preview";
    }

    function sessionPreviewSubtitle() {
        const entry = activeLauncherSessionEntry();
        if (entry && (stringOrEmpty(entry.source) === "herdr" || stringOrEmpty(entry.pane_id))) {
            return sessionSecondaryLabel(entry);
        }
        const bits = [];
        const host = stringOrEmpty(sessionPreview.host_name);
        const project = shortProject(stringOrEmpty(sessionPreview.project_name));
        const availability = sessionAvailabilityLabel(sessionPreview);
        if (host) {
            bits.push(displayHostName(host));
        }
        if (project && project !== "Global") {
            bits.push(project);
        }
        if (availability.length > 0 && sessionAvailabilityState(sessionPreview) !== "local_window") {
            bits.push(availability);
        }
        return bits.join("  •  ");
    }

    function sessionPreviewBody() {
        const content = stringOrEmpty(sessionPreview.content);
        if (content) {
            return content;
        }
        return stringOrEmpty(sessionPreview.message);
    }

    function sessionPreviewBadgeText() {
        if (stringOrEmpty(sessionPreview.status) === "loading") {
            return "Loading";
        }
        if (stringOrEmpty(sessionPreview.status) === "focus_required") {
            return "Focus";
        }
        if (boolOrFalse(sessionPreview.is_live)) {
            return "Live";
        }
        if (boolOrFalse(sessionPreview.is_remote)) {
            return "Remote";
        }
        if (stringOrEmpty(sessionPreview.status) === "error") {
            return "Error";
        }
        return "Info";
    }

    function sessionPreviewStatusText() {
        return herdrStatusLabel(sessionPreview);
    }

    function sessionLauncherEntry(session) {
        const parentWindow = findWindowById(Number(session && session.window_id || 0));
        return Object.assign({}, session, {
            kind: "session",
            identifier: stringOrEmpty(session && session.session_key),
            text: sessionPrimaryLabel(session),
            subtext: sessionSecondaryLabel(session),
            badge_label: sessionBadgeLabel(session),
            host_label: sessionHostLabel(session),
            host_token: sessionHostToken(session),
            project_label: shortProject(stringOrEmpty(session && (session.project_name || session.project || "global"))),
            window_title: parentWindow ? stringOrEmpty(displayTitle(parentWindow)) : ""
        });
    }

    function launcherSessionMatches(session, tokens) {
        const parentWindow = findWindowById(Number(session && session.window_id || 0));
        const hostTokenData = sessionHostToken(session);
        return launcherTokensMatch(tokens, [sessionPrimaryLabel(session), sessionSecondaryLabel(session), sessionBadgeLabel(session), compactSessionStateLabel(session), sessionAvailabilityLabel(session), sessionTurnOwnerLabel(session), sessionActivitySubstateLabel(session), toolLabel(session), sessionHostLabel(session), stringOrEmpty(hostTokenData && hostTokenData.label), sessionIdentityLabel(session), sessionPaneLocatorLabel(session), sessionPidLabel(session), stringOrEmpty(session && session.project_name), stringOrEmpty(session && session.project), parentWindow ? stringOrEmpty(displayTitle(parentWindow)) : ""]);
    }

    function launcherSessionHostSortKey(session) {
        const connectionKey = stringOrEmpty(session && session.connection_key);
        if (connectionKey) {
            return connectionKey;
        }

        const contextKey = stringOrEmpty(session && session.context_key);
        if (contextKey) {
            return contextKey;
        }

        return stringOrEmpty(session && session.host_name);
    }

    function launcherSessionCompare(left, right) {
        let result = compareAscending(launcherSessionHostSortKey(left), launcherSessionHostSortKey(right));
        if (result !== 0) {
            return result;
        }

        result = compareAscending(stringOrEmpty(left && left.project_name || left && left.project), stringOrEmpty(right && right.project_name || right && right.project));
        if (result !== 0) {
            return result;
        }

        result = compareAscending(sessionWindowSlot(left), sessionWindowSlot(right));
        if (result !== 0) {
            return result;
        }

        result = compareAscending(sessionPaneSlot(left), sessionPaneSlot(right));
        if (result !== 0) {
            return result;
        }

        result = compareAscending(stringOrEmpty(left && left.tool), stringOrEmpty(right && right.tool));
        if (result !== 0) {
            return result;
        }

        return compareAscending(sessionIdentityKey(left), sessionIdentityKey(right));
    }

    function launcherSessionEntries(query) {
        const tokens = launcherQueryTokens(query);
        const sessions = activeSessions().filter(function(session) {
            return sessionIsDisplayEligible(session) && launcherSessionMatches(session, tokens);
        }).slice();
        sessions.sort((left, right) => launcherSessionCompare(left, right));

        const entries = [];
        for (let i = 0; i < sessions.length; i += 1) {
            entries.push(sessionLauncherEntry(sessions[i]));
        }
        return entries;
    }

    function launcherSessionSwitcherEntries() {
        const entries = [];
        const sessions = arrayOrEmpty(sessionMru()).filter(session => sessionIsDisplayEligible(session));
        for (let i = 0; i < sessions.length; i += 1) {
            entries.push(sessionLauncherEntry(sessions[i]));
        }
        return entries;
    }

    function launcherWindowSwitcherEntries() {
        return launcherWindowEntries("");
    }

    function launcherWindowMatches(windowData, tokens) {
        const hostTokenData = windowHostToken(windowData);
        return launcherTokensMatch(tokens, [displayTitle(windowData), displayMeta(windowData), appLabel(windowData), stringOrEmpty(windowData && windowData.project), stringOrEmpty(windowData && windowData.workspace), stringOrEmpty(windowData && windowData.output), stringOrEmpty(windowData && windowData.execution_mode), stringOrEmpty(hostTokenData && hostTokenData.label)]);
    }

    function launcherWindowProjects(query) {
        const tokens = launcherQueryTokens(query);
        const allProjects = arrayOrEmpty(dashboard.projects);
        const projects = [];
        for (let p = 0; p < allProjects.length; p += 1) {
            const projectGroup = allProjects[p];
            const visibleWindows = arrayOrEmpty(projectGroup && projectGroup.windows).filter(function (windowData) {
                return !windowIsCurrentTarget(windowData);
            });
            if (!visibleWindows.length) {
                continue;
            }
            projects.push(Object.assign({}, projectGroup, {
                windows: visibleWindows
            }));
        }
        if (!tokens.length) {
            return projects;
        }

        const filteredProjects = [];
        for (let i = 0; i < projects.length; i += 1) {
            const projectGroup = projects[i];
            const matchedWindows = arrayOrEmpty(projectGroup && projectGroup.windows).filter(function (windowData) {
                return launcherWindowMatches(windowData, tokens);
            });
            if (!matchedWindows.length) {
                continue;
            }
            filteredProjects.push(Object.assign({}, projectGroup, {
                windows: matchedWindows
            }));
        }
        return filteredProjects;
    }

    function launcherWindowEntries(query) {
        const entries = [];
        const projects = launcherWindowProjects(query);
        for (let i = 0; i < projects.length; i += 1) {
            const windows = arrayOrEmpty(projects[i] && projects[i].windows);
            for (let j = 0; j < windows.length; j += 1) {
                entries.push(Object.assign({}, windows[j], {
                    kind: "window",
                    identifier: String(Number(windows[j] && (windows[j].id || windows[j].window_id) || 0)),
                    text: displayTitle(windows[j]),
                    subtext: displayMeta(windows[j]),
                    host_token: windowHostToken(windows[j])
                }));
            }
        }
        return entries;
    }

    function launcherEntryIdentity(entry) {
        const kind = stringOrEmpty(entry && entry.kind);
        if (kind === "session") {
            return "session::" + stringOrEmpty(entry && entry.session_key);
        }
        if (kind === "window") {
            return "window::" + String(Number(entry && (entry.id || entry.window_id) || 0));
        }
        const identityValue = stringOrEmpty(entry && (entry.identifier || entry.qualified_name || entry.text || entry.subtext));
        if (!identityValue) {
            return "";
        }
        if (!kind) {
            return "app::" + identityValue;
        }
        return kind + "::" + identityValue;
    }

    function launcherEntryModelKey(entry, indexHint) {
        const identity = launcherEntryIdentity(entry);
        if (identity) {
            return identity;
        }

        const numericIndex = Number(indexHint || 0);
        const safeIndex = isNaN(numericIndex) ? 0 : Math.max(0, Math.floor(numericIndex));
        return "launcher::" + String(safeIndex);
    }

    function normalizeLauncherEntries(entries) {
        const sourceEntries = arrayOrEmpty(entries);
        const normalized = [];
        for (let i = 0; i < sourceEntries.length; i += 1) {
            const entry = sourceEntries[i];
            if (!entry || typeof entry !== "object") {
                continue;
            }
            normalized.push(Object.assign({}, entry, {
                model_key: launcherEntryModelKey(entry, i)
            }));
        }
        return normalized;
    }

    function orderedLauncherSessionEntries(entries) {
        const nextEntries = arrayOrEmpty(entries);
        if (launcherMode !== "sessions") {
            return nextEntries;
        }

        const previousOrder = arrayOrEmpty(launcherSessionEntryOrder);
        if (!previousOrder.length) {
            launcherSessionEntryOrder = nextEntries.map(function(entry) {
                return launcherEntryIdentity(entry);
            }).filter(function(identity) {
                return identity.length > 0;
            });
            return nextEntries;
        }

        const remainingByIdentity = {};
        for (let i = 0; i < nextEntries.length; i += 1) {
            const entry = nextEntries[i];
            const identity = launcherEntryIdentity(entry);
            if (!identity) {
                continue;
            }
            remainingByIdentity[identity] = entry;
        }

        const ordered = [];
        const seen = {};
        for (let i = 0; i < previousOrder.length; i += 1) {
            const identity = previousOrder[i];
            if (!identity || !remainingByIdentity[identity]) {
                continue;
            }
            ordered.push(remainingByIdentity[identity]);
            seen[identity] = true;
        }

        for (let i = 0; i < nextEntries.length; i += 1) {
            const entry = nextEntries[i];
            const identity = launcherEntryIdentity(entry);
            if (identity && seen[identity]) {
                continue;
            }
            ordered.push(entry);
            if (identity) {
                seen[identity] = true;
            }
        }

        launcherSessionEntryOrder = ordered.map(function(entry) {
            return launcherEntryIdentity(entry);
        }).filter(function(identity) {
            return identity.length > 0;
        });

        return ordered;
    }

    function setLauncherEntries(entries) {
        const nextEntries = normalizeLauncherEntries(orderedLauncherSessionEntries(entries));
        const previousIdentity = launcherEntryIdentity(activeLauncherEntry());
        launcherEntries = nextEntries;

        if (!nextEntries.length) {
            launcherSelectedIndex = 0;
            launcherViewportPrimed = false;
            resetLauncherListViewport();
            if (launcherMode === "sessions") {
                clearSessionPreview();
            }
            return;
        }

        if (previousIdentity) {
            const previousIndex = nextEntries.findIndex(function (candidate) {
                return launcherEntryIdentity(candidate) === previousIdentity;
            });
            if (previousIndex >= 0) {
                launcherSelectedIndex = previousIndex;
                if (previousIndex > 0 || launcherSelectionMode !== "initial") {
                    launcherViewportPrimed = true;
                }
                syncLauncherListSelection();
                if (launcherMode === "sessions") {
                    ensureSessionPreviewForSelection();
                }
                return;
            }
        }

        launcherSelectedIndex = Math.max(0, Math.min(launcherSelectedIndex, nextEntries.length - 1));
        syncLauncherListSelection();
        if (launcherMode === "sessions") {
            ensureSessionPreviewForSelection();
        }
    }

    function normalizeSettingsSection(section) {
        const meta = settingsSectionMeta(section);
        return stringOrEmpty(meta && meta.id) || "commands";
    }

    function setSettingsSection(section) {
        settingsSection = normalizeSettingsSection(section);
        if (settingsSection === "devices") {
            resetLidPolicyDraft();
        }
    }

    function openSettings(section) {
        setSettingsSection(section);
        powerMenuVisible = false;
        audioPopupVisible = false;
        bluetoothPopupVisible = false;
        displaySelectorVisible = false;
        displaySelectorOutputName = "";
        if (settingsSection === "devices") {
            resetLidPolicyDraft();
        }
        settingsVisible = true;
    }

    function closeSettings() {
        settingsVisible = false;
    }

    function activeSettingsCommandEntry() {
        const entries = arrayOrEmpty(settingsCommandEntries);
        if (!entries.length) {
            return null;
        }
        if (settingsCommandSelectedIndex < 0 || settingsCommandSelectedIndex >= entries.length) {
            return entries[0];
        }
        return entries[settingsCommandSelectedIndex];
    }

    function setSettingsCommandEntries(entries) {
        const nextEntries = arrayOrEmpty(entries);
        const previousIdentity = launcherEntryIdentity(activeSettingsCommandEntry());
        settingsCommandEntries = nextEntries;

        if (!nextEntries.length) {
            settingsCommandSelectedIndex = 0;
            return;
        }

        if (snippetEditorSelectionHint >= 0) {
            settingsCommandSelectedIndex = Math.max(0, Math.min(snippetEditorSelectionHint, nextEntries.length - 1));
            snippetEditorSelectionHint = -1;
            return;
        }

        if (previousIdentity) {
            const previousIndex = nextEntries.findIndex(function (candidate) {
                return launcherEntryIdentity(candidate) === previousIdentity;
            });
            if (previousIndex >= 0) {
                settingsCommandSelectedIndex = previousIndex;
                return;
            }
        }

        settingsCommandSelectedIndex = Math.max(0, Math.min(settingsCommandSelectedIndex, nextEntries.length - 1));
    }

    function resetSnippetEditor() {
        snippetEditorSyncing = true;
        snippetEditorBusy = false;
        snippetEditorError = "";
        snippetEditorMessage = "";
        snippetEditorIndex = -1;
        snippetEditorSelectionHint = -1;
        snippetEditorNewDraft = false;
        snippetEditorDirty = false;
        snippetEditorLoadedIdentity = "";
        snippetEditorName = "";
        snippetEditorCommand = "";
        snippetEditorDescription = "";
        snippetEditorSyncing = false;
    }

    function activeSnippetEntry() {
        const entry = activeSettingsCommandEntry();
        if (stringOrEmpty(entry && entry.kind) !== "snippet") {
            return null;
        }
        return entry;
    }

    function snippetEditorTitle() {
        return snippetEditorNewDraft ? "New Command" : "Edit Command";
    }

    function snippetEditorStatus() {
        if (snippetEditorError) {
            return snippetEditorError;
        }
        if (snippetEditorBusy) {
            return "Saving curated command";
        }
        if (snippetEditorMessage) {
            return snippetEditorMessage;
        }
        if (snippetEditorDirty) {
            return "Unsaved changes";
        }
        if (snippetEditorNewDraft) {
            return "Create a curated command saved to Elephant snippets";
        }
        return "Selected command is stored in Elephant snippets";
    }

    function snippetEditorCanSave() {
        return stringOrEmpty(snippetEditorName).trim().length > 0 && stringOrEmpty(snippetEditorCommand).trim().length > 0 && !snippetEditorBusy;
    }

    function startSnippetDraft() {
        snippetEditorSyncing = true;
        snippetEditorError = "";
        snippetEditorMessage = "";
        snippetEditorIndex = -1;
        snippetEditorSelectionHint = -1;
        snippetEditorNewDraft = true;
        snippetEditorDirty = false;
        snippetEditorLoadedIdentity = "";
        snippetEditorName = stringOrEmpty(snippetEditorName).trim() ? snippetEditorName : stringOrEmpty(settingsCommandQuery).trim();
        snippetEditorCommand = stringOrEmpty(snippetEditorCommand).trim() ? snippetEditorCommand : "";
        snippetEditorDescription = stringOrEmpty(snippetEditorDescription).trim() ? snippetEditorDescription : "";
        snippetEditorSyncing = false;
    }

    function loadSnippetEditor(entry) {
        if (stringOrEmpty(entry && entry.kind) !== "snippet") {
            startSnippetDraft();
            return;
        }
        snippetEditorSyncing = true;
        snippetEditorError = "";
        snippetEditorMessage = "";
        snippetEditorIndex = Number(entry && entry.index);
        snippetEditorSelectionHint = snippetEditorIndex;
        snippetEditorNewDraft = false;
        snippetEditorDirty = false;
        snippetEditorLoadedIdentity = launcherEntryIdentity(entry);
        snippetEditorName = stringOrEmpty(entry && entry.text);
        snippetEditorCommand = stringOrEmpty(entry && entry.command);
        snippetEditorDescription = stringOrEmpty(entry && entry.description);
        snippetEditorSyncing = false;
    }

    function syncSnippetEditorFromSelection() {
        if (!settingsVisible || settingsSection !== "commands" || snippetEditorBusy) {
            return;
        }
        const entry = activeSnippetEntry();
        if (!entry) {
            if (!snippetEditorNewDraft || (!settingsCommandEntries.length && !stringOrEmpty(snippetEditorName).trim() && !stringOrEmpty(snippetEditorCommand).trim())) {
                startSnippetDraft();
            }
            return;
        }
        const identity = launcherEntryIdentity(entry);
        if (!snippetEditorNewDraft && snippetEditorLoadedIdentity === identity && snippetEditorIndex === Number(entry && entry.index)) {
            return;
        }
        loadSnippetEditor(entry);
    }

    function beginNewSnippetFromQuery() {
        snippetEditorSyncing = true;
        snippetEditorName = stringOrEmpty(settingsCommandQuery).trim();
        snippetEditorCommand = "";
        snippetEditorDescription = "";
        snippetEditorSyncing = false;
        startSnippetDraft();
    }

    function submitSnippetMutation(command) {
        if (snippetEditorProcess.running) {
            snippetEditorProcess.running = false;
        }
        snippetEditorBusy = true;
        snippetEditorError = "";
        snippetEditorMessage = "";
        snippetEditorProcess.command = command;
        snippetEditorProcess.running = true;
    }

    function saveSnippetEditor() {
        if (!snippetEditorCanSave()) {
            snippetEditorError = "Command name and command text are required";
            return;
        }
        submitSnippetMutation([shellConfig.snippetsManageBin, "upsert", String(snippetEditorNewDraft ? -1 : snippetEditorIndex), stringOrEmpty(snippetEditorName).trim(), stringOrEmpty(snippetEditorCommand).trim(), stringOrEmpty(snippetEditorDescription).trim()]);
    }

    function removeSnippetEditorEntry() {
        if (snippetEditorBusy || snippetEditorNewDraft || snippetEditorIndex < 0) {
            return;
        }
        submitSnippetMutation([shellConfig.snippetsManageBin, "remove", String(snippetEditorIndex)]);
    }

    function moveSnippetEditorEntry(direction) {
        if (snippetEditorBusy || snippetEditorNewDraft || snippetEditorIndex < 0) {
            return;
        }
        submitSnippetMutation([shellConfig.snippetsManageBin, "move", String(snippetEditorIndex), direction]);
    }

    function handleSnippetMutationResult(data) {
        const raw = stringOrEmpty(data).trim();
        if (!raw) {
            snippetEditorBusy = false;
            return;
        }
        try {
            const parsed = JSON.parse(raw);
            snippetEditorBusy = false;
            snippetEditorError = "";
            snippetEditorMessage = stringOrEmpty(parsed && parsed.message);
            if (parsed && parsed.index !== undefined && parsed.index !== null) {
                snippetEditorSelectionHint = Number(parsed.index);
            }
            if (stringOrEmpty(parsed && parsed.action) === "remove") {
                snippetEditorLoadedIdentity = "";
                snippetEditorNewDraft = false;
            }
            settingsCommandQueryDebounce.restart();
            if (launcherVisible && launcherMode === "snippets") {
                launcherQueryDebounce.restart();
            }
        } catch (error) {
            snippetEditorBusy = false;
            snippetEditorError = "Unable to update curated commands";
            console.warn("settings.commands.mutation:", raw, error);
        }
    }

    function settingsTitle() {
        const meta = settingsSectionMeta(settingsSection);
        return stringOrEmpty(meta && meta.title) || "Settings";
    }

    function settingsCommandStatusText() {
        if (settingsCommandError) {
            return settingsCommandError;
        }
        if (settingsCommandLoading) {
            return "Loading commands";
        }
        if (settingsCommandEntries.length) {
            return settingsCommandEntries.length + " command" + (settingsCommandEntries.length === 1 ? "" : "s");
        }
        return "No commands match the current query";
    }

    function settingsCommandEmptyText() {
        if (settingsCommandError) {
            return settingsCommandError;
        }
        return settingsCommandQuery.trim().length ? "No commands match the current query" : "No commands yet. Create one from the editor.";
    }

    function moveSettingsCommandSelection(delta) {
        const entries = arrayOrEmpty(settingsCommandEntries);
        if (!entries.length) {
            settingsCommandSelectedIndex = 0;
            return;
        }
        settingsCommandSelectedIndex = (settingsCommandSelectedIndex + delta + entries.length) % entries.length;
    }

    function restartSettingsCommandQuery() {
        if (!settingsVisible || settingsSection !== "commands") {
            return;
        }

        settingsCommandError = "";

        if (settingsCommandQueryProcess.running) {
            settingsCommandQueryProcess.running = false;
        }

        settingsCommandLoading = true;
        settingsCommandQueryProcess.command = [shellConfig.snippetsListBin, settingsCommandQuery, "200"];
        settingsCommandQueryProcess.running = true;
    }

    function parseSettingsCommandResults(data) {
        if (!settingsVisible || settingsSection !== "commands") {
            return;
        }

        const raw = stringOrEmpty(data).trim();
        if (!raw) {
            setSettingsCommandEntries([]);
            settingsCommandLoading = false;
            return;
        }

        try {
            const parsed = JSON.parse(raw);
            setSettingsCommandEntries(Array.isArray(parsed) ? parsed : []);
            if (!settingsCommandEntries.length && !snippetEditorBusy) {
                startSnippetDraft();
            }
            settingsCommandLoading = false;
            settingsCommandError = "";
        } catch (error) {
            setSettingsCommandEntries([]);
            settingsCommandLoading = false;
            settingsCommandError = "Unable to load commands";
            console.warn("settings.commands.parse:", raw, error);
        }
    }

    function herdrDashboard() {
        const herdr = dashboard && typeof dashboard.herdr === "object" ? dashboard.herdr : {};
        return herdr || {};
    }

    function herdrSpaces() {
        return arrayOrEmpty(herdrDashboard().spaces);
    }

    function herdrSpaceKey(space) {
        return stringOrEmpty(space && space.space_key) || [
            stringOrEmpty(space && (space.host_key || space.host_label)).toLowerCase(),
            stringOrEmpty(space && space.workspace_id)
        ].join("::");
    }

    function herdrSpaceGroupKey(space) {
        return stringOrEmpty(space && space.group_key) || herdrSpaceKey(space);
    }

    function herdrSpaceGroupCollapsed(groupKey) {
        const key = stringOrEmpty(groupKey);
        return key.length > 0 && collapsedHerdrSpaceGroups[key] === true;
    }

    function herdrSpaceIsFocused(space) {
        const focus = dashboardFocusState();
        const currentPaneId = stringOrEmpty(focus.current_herdr_pane_id);
        if (currentPaneId.length === 0) {
            return false;
        }

        const currentHost = normalizeHostAlias(focus.current_herdr_host);
        const targetSpaceKey = herdrSpaceKey(space);
        const targetWorkspaceId = stringOrEmpty(space && space.workspace_id);
        const targetHost = normalizeHostAlias(space && (space.host_key || space.host_label));
        const sessions = activeSessions();
        for (let i = 0; i < sessions.length; i += 1) {
            const session = sessions[i];
            const sessionPaneId = stringOrEmpty(session && session.pane_id);
            if (sessionPaneId !== currentPaneId) {
                continue;
            }

            const sessionHost = normalizeHostAlias(session && (session.herdr_host || session.host_name));
            if (currentHost.length > 0 && sessionHost.length > 0 && currentHost !== sessionHost) {
                continue;
            }

            const sessionSpace = herdrSessionSpace(session);
            if (sessionSpace && herdrSpaceKey(sessionSpace) === targetSpaceKey) {
                return true;
            }

            if (
                targetWorkspaceId.length > 0
                && targetWorkspaceId === stringOrEmpty(session && session.workspace_id)
                && (!targetHost.length || !sessionHost.length || targetHost === sessionHost)
            ) {
                return true;
            }
        }

        return false;
    }

    function toggleHerdrSpaceGroup(groupKey) {
        const key = stringOrEmpty(groupKey);
        if (!key) {
            return;
        }
        const next = Object.assign({}, collapsedHerdrSpaceGroups);
        if (next[key] === true) {
            delete next[key];
        } else {
            next[key] = true;
        }
        collapsedHerdrSpaceGroups = next;
    }

    function herdrSpacesInGroup(groupKey) {
        const key = stringOrEmpty(groupKey);
        if (!key) {
            return [];
        }
        return herdrSpaces().filter(function(space) {
            return herdrSpaceGroupKey(space) === key;
        });
    }

    function herdrSpaceStatusPriority(status) {
        const state = herdrStatusState(status);
        if (state === "blocked") {
            return 5;
        }
        if (state === "done") {
            return 4;
        }
        if (state === "working") {
            return 3;
        }
        if (state === "idle") {
            return 2;
        }
        return 1;
    }

    function herdrAggregateStatusForGroup(groupKey) {
        const members = herdrSpacesInGroup(groupKey);
        let best = "unknown";
        let bestPriority = 0;
        for (let i = 0; i < members.length; i += 1) {
            const status = herdrSpaceStatus(members[i]);
            const priority = herdrSpaceStatusPriority(status);
            if (priority > bestPriority) {
                best = status;
                bestPriority = priority;
            }
        }
        return best;
    }

    function herdrSpaceEffectiveStatus(space) {
        if (root.boolOrFalse(space && space.is_group_parent) && herdrSpaceGroupCollapsed(herdrSpaceGroupKey(space))) {
            return herdrAggregateStatusForGroup(herdrSpaceGroupKey(space));
        }
        return herdrSpaceStatus(space);
    }

    function runtimePanelDefaultExpandedSection() {
        if (panelSessions().length > 0 || herdrSpaces().length > 0) {
            return "sessions";
        }
        return "";
    }

    function runtimePanelExpandedSectionValue() {
        const requested = stringOrEmpty(runtimePanelExpandedSection);
        const hasSessions = panelSessions().length > 0 || herdrSpaces().length > 0;

        if (requested === "sessions" && hasSessions) {
            return "sessions";
        }
        return runtimePanelDefaultExpandedSection();
    }

    function runtimePanelSectionHasContent(section) {
        if (section === "sessions") {
            return panelSessions().length > 0 || herdrSpaces().length > 0;
        }
        return false;
    }

    function herdrSpaceStatus(space) {
        return herdrStatusStateFor(space);
    }

    function herdrSpaceStatusColor(space) {
        const state = herdrSpaceEffectiveStatus(space);
        if (state === "blocked") {
            return colors.red;
        }
        if (state === "working") {
            return colors.amber;
        }
        if (state === "done") {
            return colors.teal;
        }
        if (state === "idle") {
            return colors.green;
        }
        return colors.muted;
    }

    function herdrStatusIcon(state, spinnerFrame) {
        const normalized = herdrStatusState(state);
        if (normalized === "blocked") {
            return "◉";
        }
        if (normalized === "working") {
            const frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
            const frame = Number(spinnerFrame || 0);
            return frames[Math.max(0, Math.trunc(frame)) % frames.length];
        }
        if (normalized === "done") {
            return "●";
        }
        if (normalized === "idle") {
            return "✓";
        }
        return "○";
    }

    function herdrSpaceStatusDot(space, spinnerFrame) {
        const state = herdrSpaceEffectiveStatus(space);
        return herdrStatusIcon(state, spinnerFrame);
    }

    function herdrSpaceFill(space, hovered) {
        if (herdrSpaceIsFocused(space)) {
            return hovered
                ? Qt.tint(colors.cardAlt, Qt.rgba(0.40, 0.86, 0.92, 0.11))
                : Qt.tint(colors.cardAlt, Qt.rgba(0.40, 0.86, 0.92, 0.07));
        }
        return hovered ? colors.cardAlt : "transparent";
    }

    function herdrSpaceBorder(space, hovered) {
        if (herdrSpaceIsFocused(space)) {
            return hovered ? colors.lineSoft : "transparent";
        }
        return hovered ? colors.lineSoft : "transparent";
    }

    function herdrSpaceBranchLabel(space) {
        const branchLabel = stringOrEmpty(space && space.branch_label);
        if (branchLabel.indexOf("worktree/") === 0) {
            return branchLabel.slice(9);
        }
        return branchLabel;
    }

    function herdrSpaceTitle(space) {
        if (boolOrFalse(space && space.is_linked_worktree)) {
            const label = stringOrEmpty(space && space.label);
            const branchLabel = herdrSpaceBranchLabel(space);
            if (label.length > 0 && label !== stringOrEmpty(space && space.repo_name)) {
                return label;
            }
            if (branchLabel.length > 0) {
                return branchLabel;
            }
        }
        const label = stringOrEmpty(space && space.label);
        if (label.length > 0) {
            return label;
        }
        const project = shortProject(stringOrEmpty(space && space.project_name));
        if (project && project !== "Global") {
            return project;
        }
        return "Workspace";
    }

    function herdrSpaceMetaLabel(space) {
        const branch = herdrSpaceBranchLabel(space);
        return branch;
    }

    function herdrSpaceGitSnapshot(space) {
        const snapshot = space && space.git_snapshot;
        return snapshot && typeof snapshot === "object" ? snapshot : ({});
    }

    function herdrSpaceGitState(space) {
        const directState = stringOrEmpty(space && space.git_state).toLowerCase();
        if (directState.length > 0) {
            return directState;
        }
        return stringOrEmpty(herdrSpaceGitSnapshot(space).state).toLowerCase() || "unknown";
    }

    function herdrSpaceGitFreshness(space) {
        const directFreshness = stringOrEmpty(space && space.git_freshness).toLowerCase();
        if (directFreshness.length > 0) {
            return directFreshness;
        }
        return stringOrEmpty(herdrSpaceGitSnapshot(space).freshness).toLowerCase();
    }

    function herdrSpaceGitChipText(space) {
        const snapshot = herdrSpaceGitSnapshot(space);
        const compact = stringOrEmpty(space && space.git_compact) || stringOrEmpty(snapshot.status_compact);
        const freshness = herdrSpaceGitFreshness(space);
        if (!compact && freshness !== "stale") {
            return "";
        }
        if (!compact) {
            return "~";
        }
        return freshness === "stale" ? (compact + " ~") : compact;
    }

    function herdrSpaceGitChipVisible(space) {
        return herdrSpaceGitChipText(space).length > 0;
    }

    function herdrSpaceGitChipForeground(space) {
        const snapshot = herdrSpaceGitSnapshot(space);
        const state = herdrSpaceGitState(space);
        if (state === "conflicted" || state === "dirty") {
            return colors.red;
        }
        if (Number(snapshot.behind || 0) > 0) {
            return colors.red;
        }
        if (Number(snapshot.ahead || 0) > 0) {
            return colors.green;
        }
        return colors.muted;
    }

    function herdrSpaceGitChipBackground(space) {
        const snapshot = herdrSpaceGitSnapshot(space);
        const state = herdrSpaceGitState(space);
        if (state === "conflicted" || state === "dirty") {
            return Qt.tint(colors.panelAlt, Qt.rgba(0.99, 0.64, 0.69, 0.08));
        }
        if (Number(snapshot.behind || 0) > 0) {
            return Qt.tint(colors.panelAlt, Qt.rgba(0.99, 0.64, 0.69, 0.07));
        }
        if (Number(snapshot.ahead || 0) > 0) {
            return Qt.tint(colors.panelAlt, Qt.rgba(0.53, 0.94, 0.67, 0.06));
        }
        return Qt.tint(colors.panelAlt, Qt.rgba(0.53, 0.94, 0.67, 0.04));
    }

    function herdrSpaceGitTooltip(space) {
        const snapshot = herdrSpaceGitSnapshot(space);
        const tooltip = stringOrEmpty(space && space.git_tooltip) || stringOrEmpty(snapshot.status_tooltip);
        if (tooltip.length > 0) {
            return tooltip;
        }
        const compact = herdrSpaceGitChipText(space);
        const branch = herdrSpaceBranchLabel(space);
        const parts = [];
        if (branch.length > 0) {
            parts.push("Branch: " + branch);
        }
        if (compact.length > 0) {
            parts.push("Git: " + compact);
        }
        return parts.join("\n");
    }

    function herdrSpaceIndent(space) {
        return boolOrFalse(space && space.is_linked_worktree) && stringOrEmpty(space && space.group_key).length > 0 ? 18 : 0;
    }

    function herdrSpaceChevron(space) {
        if (!boolOrFalse(space && space.is_group_parent)) {
            return "";
        }
        return herdrSpaceGroupCollapsed(herdrSpaceGroupKey(space)) ? "▸" : "▾";
    }

    function herdrSessionSpace(session) {
        const workspaceId = stringOrEmpty(session && session.workspace_id);
        if (workspaceId.length === 0) {
            return null;
        }

        const host = stringOrEmpty(session && (session.herdr_host || session.host_name)).toLowerCase();
        const spaces = herdrSpaces();
        const expectedKey = host + "::" + workspaceId;
        for (let i = 0; i < spaces.length; i += 1) {
            const space = spaces[i];
            const spaceWorkspaceId = stringOrEmpty(space && space.workspace_id);
            const spaceHost = stringOrEmpty(space && (space.host_key || space.host_label)).toLowerCase();
            if ((spaceHost + "::" + spaceWorkspaceId) !== expectedKey) {
                continue;
            }
            return space;
        }
        if (host.length === 0) {
            return spaces.find(function(space) {
                return stringOrEmpty(space && space.workspace_id) === workspaceId;
            }) || null;
        }
        return null;
    }

    function herdrSessionSidebarTitle(session) {
        const space = herdrSessionSpace(session);
        if (space) {
            return herdrSpaceTitle(space);
        }
        const workspaceName = stringOrEmpty(session && session.workspace_name);
        if (workspaceName.length > 0) {
            return workspaceName;
        }
        const project = shortProject(stringOrEmpty(session && (session.project_name || session.project || "")));
        if (project && project !== "Global") {
            return project;
        }
        return "";
    }

    function herdrSpaceFocusTarget(space) {
        return normalizedFocusTarget(space && space.focus_target);
    }

    function focusHerdrSpace(space) {
        const target = herdrSpaceFocusTarget(space);
        if (!target) {
            return;
        }
        runFocusTarget(target);
    }

    function toggleRuntimePanelSection(section) {
        if (!runtimePanelSectionHasContent(section)) {
            return;
        }

        runtimePanelExpandedSection = section;
    }

    function ensureRuntimePanelExpandedSection() {
        runtimePanelExpandedSection = runtimePanelExpandedSectionValue();
    }

    function showRuntimePanelSection(section, outputName) {
        const requested = stringOrEmpty(section);
        showRuntimePanel(outputName);
        if (runtimePanelSectionHasContent(requested)) {
            runtimePanelExpandedSection = requested;
            return;
        }
        ensureRuntimePanelExpandedSection();
    }

    function togglePanelVisibility(outputName) {
        if (panelVisible) {
            panelVisible = false;
            return;
        }
        showRuntimePanel(outputName);
    }

    function currentSessionKey() {
        return stringOrEmpty(dashboardFocusState().current_session_key);
    }

    function sessionMatchesKey(session, key) {
        const target = stringOrEmpty(key);
        if (!session || !target) {
            return false;
        }
        const candidates = [
            stringOrEmpty(session && session.session_key),
            stringOrEmpty(session && session.render_session_key),
            stringOrEmpty(session && session.herdr_session),
            sessionIdentityKey(session),
        ];
        for (let i = 0; i < candidates.length; i += 1) {
            if (candidates[i] && candidates[i] === target) {
                return true;
            }
        }
        return false;
    }

   function worktreeStatusLabel(item) {
        if (!item || stringOrEmpty(item.kind) === "global") {
            return "";
        }
        if (boolOrFalse(item.has_conflicts)) {
            return "Conflict";
        }
        if (!boolOrFalse(item.is_clean)) {
            return "Dirty";
        }
        if (boolOrFalse(item.is_stale)) {
            return "Stale";
        }
        return "Clean";
    }

    function worktreeStatusColor(item) {
        if (!item || stringOrEmpty(item.kind) === "global") {
            return colors.subtle;
        }
        if (boolOrFalse(item.has_conflicts)) {
            return colors.red;
        }
        if (!boolOrFalse(item.is_clean)) {
            return colors.amber;
        }
        if (boolOrFalse(item.is_stale)) {
            return colors.blue;
        }
        return colors.accent;
    }

    function toolIconSource(session) {
        const tool = stringOrEmpty(session.tool).toLowerCase();
        if (tool === "codex") {
            return "file://" + shellConfig.codexIcon;
        }
        if (tool === "claude-code" || tool === "claude") {
            return "file://" + shellConfig.claudeIcon;
        }
        if (tool === "gemini" || tool === "gemini-cli" || tool === "antigravity" || tool === "antigravity-cli" || tool === "agy") {
            return "file://" + shellConfig.geminiIcon;
        }
        return "file://" + shellConfig.aiFallbackIcon;
    }

    function projectTargetHostIsCurrentHost(entry) {
        const targetHost = normalizeHostAlias(entry && entry.target_host);
        const currentHost = currentHostAlias();
        return !targetHost || !currentHost || targetHost === currentHost;
    }

    function projectTargetHostFill(entry) {
        return projectTargetHostIsCurrentHost(entry) ? colors.blueWash : colors.orangeBg;
    }

    function projectTargetHostBorder(entry) {
        return projectTargetHostIsCurrentHost(entry) ? colors.blueMuted : colors.orange;
    }

    function projectTargetHostText(entry) {
        return projectTargetHostIsCurrentHost(entry) ? colors.blue : colors.orange;
    }

    function projectTargetHostLabel(entry) {
        return stringOrEmpty(entry && entry.target_host);
    }
   function sessionGroupFill(group) {
        if (boolOrFalse(group && group.is_current_host)) {
            return colors.panelAlt;
        }
        return colors.cardAlt;
    }

    function titleCaseWord(value) {
        const text = stringOrEmpty(value).trim();
        if (!text.length) {
            return "";
        }
        return text.charAt(0).toUpperCase() + text.slice(1);
    }

    function displayHostName(value) {
        const host = stringOrEmpty(value).trim().toLowerCase();
        if (!host.length) {
            return "";
        }

        const pieces = host.split(/[^a-z0-9]+/).filter(part => part.length > 0);
        if (!pieces.length) {
            return titleCaseWord(host);
        }
        return pieces.map(part => titleCaseWord(part)).join(" ");
    }

    function hostNameFromConnectionKey(value) {
        let key = stringOrEmpty(value).trim();
        if (!key.length) {
            return "";
        }

        const atIndex = key.lastIndexOf("@");
        if (atIndex >= 0 && atIndex < key.length - 1) {
            key = key.slice(atIndex + 1);
        }

        const slashIndex = key.indexOf("/");
        if (slashIndex > 0) {
            key = key.slice(0, slashIndex);
        }

        const colonIndex = key.lastIndexOf(":");
        if (colonIndex > 0 && /^[0-9]+$/.test(key.slice(colonIndex + 1))) {
            key = key.slice(0, colonIndex);
        }

        return displayHostName(key);
    }

    function localHostDisplayName() {
        return displayHostName(shellConfig.hostName) || "Local";
    }

    function resolveThemeIcon(candidates) {
        for (let i = 0; i < candidates.length; i += 1) {
            const candidate = stringOrEmpty(candidates[i]);
            if (!candidate.length) {
                continue;
            }
            const resolved = Quickshell.iconPath(candidate, true);
            if (resolved) {
                return resolved;
            }
        }
        return "";
    }

    function hostToken(mode, hostName, connectionKey) {
        const normalizedMode = stringOrEmpty(mode).toLowerCase() === "ssh" ? "ssh" : "local";
        const isRemote = normalizedMode === "ssh";
        const label = displayHostName(hostName) || hostNameFromConnectionKey(connectionKey) || (isRemote ? "Remote" : localHostDisplayName());
        const icon = isRemote ? ("file://" + shellConfig.tailscaleIcon) : resolveThemeIcon(["computer-symbolic", "computer-laptop-symbolic", "video-display-symbolic", "desktop-symbolic"]);

        return {
            label: label,
            icon: icon,
            is_remote: isRemote,
            foreground: colors.blue,
            background: isRemote ? colors.blueBg : colors.blueWash,
            border: colors.blueMuted,
            monogram: label.length ? label.charAt(0).toUpperCase() : (isRemote ? "R" : "L")
        };
    }

    function sessionHostToken(session) {
        return hostToken(stringOrEmpty(session && session.execution_mode), stringOrEmpty(session && session.host_name), stringOrEmpty(session && session.connection_key));
    }

    function spaceHostToken(space) {
        return hostToken(
            stringOrEmpty(space && space.execution_mode),
            stringOrEmpty(space && (space.host_label || space.host_key)),
            stringOrEmpty(space && space.connection_key)
        );
    }

    function sessionHostGroupKey(session) {
        const token = sessionHostToken(session);
        const label = stringOrEmpty(token && token.label).trim().toLowerCase();
        if (label.length > 0) {
            return label;
        }

        const hostName = stringOrEmpty(session && session.host_name).trim().toLowerCase();
        if (hostName.length > 0) {
            return hostName;
        }

        const mode = stringOrEmpty(session && session.execution_mode).toLowerCase() === "ssh" ? "remote" : localHostDisplayName().trim().toLowerCase();
        return mode || "unknown";
    }

    function windowHostToken(windowData) {
        return hostToken(stringOrEmpty(windowData && windowData.execution_mode), "", stringOrEmpty(windowData && windowData.connection_key));
    }

    function herdrStatusState(value) {
        const raw = stringOrEmpty(value).toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
        if (["blocked", "needs_input", "needsinput", "waiting_input", "waiting_for_input"].indexOf(raw) >= 0) {
            return "blocked";
        }
        if (["done", "complete", "completed", "success", "succeeded", "finished"].indexOf(raw) >= 0) {
            return "done";
        }
        if (["working", "running", "thinking", "streaming", "tool_running", "busy"].indexOf(raw) >= 0) {
            return "working";
        }
        if (["idle", "ready"].indexOf(raw) >= 0) {
            return "idle";
        }
        return "unknown";
    }

    function herdrStatusStateFor(item) {
        const explicit = stringOrEmpty(item && item.agent_status_state);
        if (explicit.length > 0) {
            return herdrStatusState(explicit);
        }
        return herdrStatusState(item && item.agent_status);
    }

    function herdrStateLabel(labels, rawStatus, state) {
        if (!labels || typeof labels !== "object") {
            return "";
        }
        const raw = stringOrEmpty(rawStatus);
        if (raw.length > 0) {
            const exact = stringOrEmpty(labels[raw]);
            if (exact.length > 0) {
                return exact;
            }
        }
        const visualState = stringOrEmpty(state);
        if (visualState.length > 0) {
            const direct = stringOrEmpty(labels[visualState]);
            if (direct.length > 0) {
                return direct;
            }
        }
        const rawNormalized = raw.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
        const keys = Object.keys(labels);
        for (let i = 0; i < keys.length; i += 1) {
            const key = keys[i];
            const keyNormalized = stringOrEmpty(key).toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
            if (keyNormalized === rawNormalized || keyNormalized === visualState) {
                const value = stringOrEmpty(labels[key]);
                if (value.length > 0) {
                    return value;
                }
            }
        }
        return "";
    }

    function herdrStatusLabel(session) {
        const rawStatus = stringOrEmpty(session && session.agent_status);
        const state = herdrStatusStateFor(session);
        const labels = session && session.state_labels && typeof session.state_labels === "object" ? session.state_labels : {};
        const customStatus = stringOrEmpty(session && session.custom_status);
        if (customStatus.length > 0) {
            return customStatus;
        }
        const override = herdrStateLabel(labels, rawStatus, state);
        if (override.length > 0) {
            return override;
        }
        if (rawStatus.length > 0 && rawStatus !== "unknown") {
            return rawStatus;
        }
        if (state === "unknown") {
            return "Unknown";
        }
        return titleCaseWord(state);
    }

    function sessionPhase(session) {
        return herdrStatusStateFor(session);
    }

    function sessionAccentColor(session) {
        const phase = sessionPhase(session);
        if (phase === "blocked") {
            return colors.red;
        }
        if (phase === "done") {
            return colors.teal;
        }
        if (phase === "working") {
            return colors.amber;
        }
        if (phase === "idle") {
            return colors.green;
        }
        return colors.muted;
    }

    function boolOrFalse(value) {
        return value === true;
    }

    function sessionIsIdle(session) {
        return sessionPhase(session) === "idle";
    }

    function sessionIsActivelyProcessing(session) {
        return sessionPhase(session) === "working";
    }

    function sessionHasMotion(session) {
        return sessionIsActivelyProcessing(session);
    }

    function sessionBadgeState(session) {
        return sessionPhase(session);
    }

    function sessionBadgeColor(session) {
        const state = sessionBadgeState(session);
        const hasHerdrStatus = stringOrEmpty(session && session.agent_status).length > 0;
        if (state === "blocked") {
            return colors.red;
        }
        if (state === "needs_attention") {
            return colors.amber;
        }
        if (state === "stopped") {
            return colors.violet;
        }
        if (state === "done") {
            return hasHerdrStatus ? colors.teal : colors.accent;
        }
        if (state === "working") {
            return hasHerdrStatus ? colors.amber : root.sessionAccentColor(session);
        }
        if (state === "idle") {
            return hasHerdrStatus ? colors.green : colors.subtle;
        }
        return colors.muted;
    }

    function sessionBadgeBackground(session) {
        const state = sessionBadgeState(session);
        const hasHerdrStatus = stringOrEmpty(session && session.agent_status).length > 0;
        if (state === "blocked") {
            return colors.redBg;
        }
        if (state === "needs_attention") {
            return colors.amberBg;
        }
        if (state === "stopped") {
            return Qt.tint(colors.violetBg, Qt.rgba(1, 1, 1, 0.04));
        }
        if (state === "done") {
            return hasHerdrStatus ? colors.tealBg : colors.accentBg;
        }
        if (state === "working") {
            return hasHerdrStatus ? colors.amberBg : (root.sessionIsCurrent(session) ? colors.bg : colors.cardAlt);
        }
        if (state === "idle") {
            return hasHerdrStatus ? colors.greenBg : (root.sessionIsCurrent(session) ? colors.bg : colors.cardAlt);
        }
        return colors.cardAlt;
    }

    function sessionBadgeBorderColor(session) {
        const state = sessionBadgeState(session);
        const hasHerdrStatus = stringOrEmpty(session && session.agent_status).length > 0;
        if (hasHerdrStatus) {
            return "transparent";
        }
        if (state === "blocked") {
            return colors.lineSoft;
        }
        if (state === "stopped") {
            return colors.lineSoft;
        }
        if (state === "idle") {
            return colors.lineSoft;
        }
        return "transparent";
    }

    function sessionAvailabilityState(session) {
        const explicit = stringOrEmpty(session && session.availability_state).toLowerCase();
        if (explicit.length > 0) {
            return explicit;
        }
        const focusMode = stringOrEmpty(session && session.focus_mode).toLowerCase();
        if (focusMode === "local_window") {
            return "local_window";
        }
        if (focusMode === "remote_herdr_attach") {
            return "remote_herdr_attachable";
        }
        return "unavailable";
    }

    function sessionAvailabilityLabel(session) {
        const state = sessionAvailabilityState(session);
        if (state === "remote_herdr_attachable") {
            return "Remote Herdr";
        }
        if (state === "unavailable") {
            return "Unavailable";
        }
        return "Available here";
    }

    function sessionAgeCompactLabel(session) {
        const ageSeconds = Number(session && session.activity_age_seconds);
        if (!Number.isFinite(ageSeconds) || ageSeconds < 0) {
            return "";
        }
        if (ageSeconds <= 1) {
            return "now";
        }
        if (ageSeconds < 60) {
            return String(Math.round(ageSeconds)) + "s";
        }
        if (ageSeconds < 3600) {
            return String(Math.floor(ageSeconds / 60)) + "m";
        }
        if (ageSeconds < 86400) {
            return String(Math.floor(ageSeconds / 3600)) + "h";
        }
        return String(Math.floor(ageSeconds / 86400)) + "d";
    }

    function sessionTurnOwner(session) {
        const herdrStatus = sessionPhase(session);
        if (herdrStatus === "working") {
            return "llm";
        }
        if (herdrStatus === "blocked") {
            return "blocked";
        }
        if (herdrStatus === "done" || herdrStatus === "idle") {
            return "user";
        }
        return "unknown";
    }

    function sessionTurnOwnerLabel(session) {
        const owner = sessionTurnOwner(session);
        if (owner === "llm") {
            return "LLM";
        }
        if (owner === "user") {
            return "User";
        }
        if (owner === "blocked") {
            return "Blocked";
        }
        return "Unknown";
    }

    function sessionActivitySubstateLabel(session) {
        return herdrStatusLabel(session);
    }

    function sessionBadgeLabel(session) {
        const ownerLabel = sessionTurnOwnerLabel(session);
        const substateLabel = sessionActivitySubstateLabel(session);
        if (substateLabel.length > 0 && substateLabel !== ownerLabel) {
            return ownerLabel + " · " + substateLabel;
        }
        if (ownerLabel !== "Unknown") {
            return ownerLabel;
        }
        return sessionAgeCompactLabel(session);
    }

    function sessionActivityChipLabel(session) {
        const state = sessionBadgeState(session);
        return ["working", "blocked", "done", "idle", "unknown"].indexOf(state) >= 0 ? herdrStatusLabel(session) : compactSessionStateLabel(session);
    }

    function sessionBadgeSymbol(session) {
        const owner = sessionTurnOwner(session);
        const state = sessionBadgeState(session);
        if (state === "blocked") {
            return "◉";
        }
        if (owner === "blocked") {
            return "◉";
        }
        if (state === "done") {
            return "●";
        }
        if (owner === "llm" || state === "working") {
            return "◔";
        }
        if (owner === "user") {
            return "✓";
        }
        if (state === "stale") {
            return "◌";
        }
        return "○";
    }

    function sessionIdentityLabel(session) {
        const source = stringOrEmpty(session.identity_source).toLowerCase();
        if (source === "native") {
            return "N";
        }
        if (source === "pid") {
            return "PID";
        }
        if (source === "pane") {
            return "P";
        }
        return "H";
    }

    function sessionHostLabel(session) {
        const host = displayHostName(session && session.host_name);
        if (!host) {
            return root.modeLabel(session.execution_mode);
        }
        return host;
    }

    function hostMonogram(mode, hostName, connectionKey) {
        const token = hostToken(mode, hostName, connectionKey);
        const monogram = stringOrEmpty(token && token.monogram).trim().toUpperCase();
        return monogram.length > 0 ? monogram.charAt(0) : "";
    }

    function buildSessionAlias(monogram, paneId) {
        const prefix = stringOrEmpty(monogram).trim().toUpperCase();
        const pane = stringOrEmpty(paneId).trim();
        if (!prefix.length || !pane.length) {
            return "";
        }
        return prefix.charAt(0) + pane;
    }

    function sessionAlias(session) {
        return buildSessionAlias(
            hostMonogram(
                stringOrEmpty(session && session.execution_mode),
                stringOrEmpty(session && session.host_name),
                stringOrEmpty(session && session.connection_key)
            ),
            stringOrEmpty(session && (session.pane_id || session.pane_label))
        );
    }

    function sessionPaneLabel(session) {
        const label = stringOrEmpty(session.pane_label || session.pane_title || session.pane_id);
        if (label) {
            return label;
        }
        return "";
    }

    function sessionPidLabel(session) {
        const processPid = Number(session && session.pid);
        if (Number.isFinite(processPid) && processPid > 0) {
            return "PID " + String(Math.trunc(processPid));
        }
        const panePid = Number(session && session.pane_pid);
        if (Number.isFinite(panePid) && panePid > 0) {
            return "PID " + String(Math.trunc(panePid));
        }
        return "";
    }

    function sessionPaneLocatorLabel(session) {
        const paneId = stringOrEmpty(session && session.pane_id).trim();
        if (!paneId) {
            return "";
        }
        const pane = sessionPaneLabel(session);
        if (pane && pane.indexOf(paneId) >= 0) {
            return "";
        }
        return "Pane " + paneId;
    }

    function compactSessionStateLabel(session) {
        const badgeState = sessionBadgeState(session);
        if (badgeState === "blocked") {
            return "Blocked";
        }
        if (badgeState === "needs_attention") {
            return "Needs attention";
        }
        if (badgeState === "stopped") {
            return "";
        }
        if (badgeState === "done") {
            return "Done";
        }
        if (badgeState === "quiet_alive") {
            return "Quiet";
        }
        if (badgeState === "working") {
            return "Working";
        }
        if (badgeState === "stale") {
            return "Stale";
        }
        if (badgeState === "inactive") {
            return "Inactive";
        }
        return "Idle";
    }

    function toolLabel(session) {
        const displayAgent = stringOrEmpty(session && session.display_agent);
        if (displayAgent.length > 0) {
            return displayAgent;
        }
        const tool = stringOrEmpty(session.tool).toLowerCase();
        if (tool === "codex") {
            return "Codex";
        }
        if (tool === "claude-code" || tool === "claude") {
            return "Claude";
        }
        if (tool === "gemini" || tool === "gemini-cli" || tool === "antigravity" || tool === "antigravity-cli" || tool === "agy") {
            return "Gemini";
        }
        if (tool === "opencode") {
            return "OpenCode";
        }
        if (tool === "github-copilot" || tool === "copilot") {
            return "GitHub Copilot";
        }
        if (tool === "cursor" || tool === "cursor-agent") {
            return "Cursor";
        }
        if (tool === "amp") {
            return "Amp";
        }
        if (tool === "kimi") {
            return "Kimi";
        }
        if (tool === "kiro") {
            return "Kiro";
        }
        if (tool === "droid") {
            return "Droid";
        }
        if (tool === "hermes") {
            return "Hermes";
        }
        if (tool === "qoder" || tool === "qodercli") {
            return "Qoder";
        }
        if (tool === "pi") {
            return "Pi";
        }
        if (tool === "grok") {
            return "Grok";
        }
        if (tool === "cline") {
            return "Cline";
        }
        if (tool === "kilo") {
            return "Kilo";
        }
        return "AI";
    }

    function sessionIsCurrent(session) {
        const localPendingHerdrFocus = localPendingFocusIntentFor("herdr_pane_focus");
        if (localPendingHerdrFocus) {
            const localPendingSessionTarget = sessionPendingFocusTargetKey(session, localPendingHerdrFocus);
            return focusIntentMatchesTarget(localPendingHerdrFocus, localPendingSessionTarget);
        }

        const current = currentSessionKey();
        if (current) {
            return sessionMatchesKey(session, current);
        }
        const focus = dashboardFocusState();
        const currentPaneId = stringOrEmpty(focus.current_herdr_pane_id);
        if (currentPaneId) {
            if (currentPaneId !== stringOrEmpty(session && session.pane_id)) {
                return false;
            }
            const currentHost = normalizeHostAlias(focus.current_herdr_host);
            const sessionHost = normalizeHostAlias(session && (session.herdr_host || session.host_name || session.target_host));
            if (currentHost && sessionHost && currentHost !== sessionHost) {
                return false;
            }
            return true;
        }

        const pendingHerdrFocus = pendingFocusIntentFor("herdr_pane_focus");
        if (pendingHerdrFocus) {
            const pendingSessionTarget = sessionPendingFocusTargetKey(session);
            return pendingFocusIntentMatches("herdr_pane_focus", pendingSessionTarget);
        }
        return false;
    }

    function sessionCurrentOverride(session) {
        return sessionIsCurrent(session);
    }

    function sessionPrimaryLabel(session) {
        const agent = toolLabel(session);
        const project = shortProject(stringOrEmpty(session && (session.project_name || session.project || "")));
        if (stringOrEmpty(session && session.source) === "herdr" || stringOrEmpty(session && session.pane_id)) {
            const sidebarTitle = herdrSessionSidebarTitle(session);
            if (sidebarTitle.length > 0) {
                return sidebarTitle;
            }
            const host = displayHostName(stringOrEmpty(session && (session.herdr_host || session.host_name)));
            const isRemote = boolOrFalse(session && session.is_remote_herdr);
            const bits = [agent || "AI"];
            if (project && project !== "Global") {
                bits.push(project);
            }
            if (isRemote && host) {
                bits.push(host);
            }
            return bits.join(" · ") || "AI Session";
        }
        const alias = sessionAlias(session);
        if (alias.length > 0) {
            return alias;
        }
        const pane = sessionPaneLabel(session);
        if (pane) {
            return pane;
        }
        const tool = toolLabel(session);
        return tool ? tool + " Session" : "AI Session";
    }

    function sessionSecondaryLabel(session) {
        const bits = [];
        const project = shortProject(stringOrEmpty(session && (session.project_name || session.project || "")));
        const herdrStatus = stringOrEmpty(session && session.agent_status);
        const customStatus = stringOrEmpty(session && session.custom_status);
        if (stringOrEmpty(session && session.source) === "herdr" || stringOrEmpty(session && session.pane_id)) {
            const agent = toolLabel(session);
            const host = displayHostName(stringOrEmpty(session && (session.herdr_host || session.host_name)));
            const isRemote = boolOrFalse(session && session.is_remote_herdr);
            if (agent) {
                bits.push(agent);
            }
            if (isRemote && host) {
                bits.push(host);
            }
        }
        if (herdrStatus) {
            const statusLabel = herdrStatusLabel(session);
            if (statusLabel.length > 0) {
                bits.push(statusLabel);
            }
        }
        if (customStatus && customStatus !== bits[bits.length - 1]) {
            bits.push(customStatus);
        }
        const foregroundCwd = stringOrEmpty(session && session.foreground_cwd);
        const cwd = stringOrEmpty(session && session.cwd);
        if (foregroundCwd || cwd) {
            const path = foregroundCwd || cwd;
            const parts = path.split("/").filter(part => part.length > 0);
            if (parts.length > 0) {
                bits.push(parts[parts.length - 1]);
            }
        }
        if (bits.length > 0 && (stringOrEmpty(session && session.source) === "herdr" || stringOrEmpty(session && session.pane_id))) {
            return bits.join(" • ");
        }
        const availability = sessionAvailabilityLabel(session);
        const phase = compactSessionStateLabel(session);
        if (project.length > 0 && project !== "Global") {
            bits.push(project);
        }
        if (availability.length > 0 && sessionAvailabilityState(session) !== "local_window") {
            bits.push(availability);
        }
        if (phase.length > 0 && phase !== availability) {
            bits.push(phase);
        }

        if (bits.length === 0) {
            const paneLocator = sessionPaneLocatorLabel(session);
            const pid = sessionPidLabel(session);
            if (paneLocator) {
                bits.push(paneLocator);
            }
            if (pid) {
                bits.push(pid);
            }
        }

        return bits.join(" • ");
    }

    function sessionGitState(session) {
        return stringOrEmpty(session && session.git_state).toLowerCase() || "unknown";
    }

    function sessionGitFreshness(session) {
        return stringOrEmpty(session && session.git_freshness).toLowerCase();
    }

    function sessionGitChipText(session) {
        const compact = stringOrEmpty(session && session.git_compact);
        const freshness = sessionGitFreshness(session);
        if (!compact && freshness !== "stale") {
            return "";
        }
        if (!compact) {
            return "~";
        }
        return freshness === "stale" ? (compact + " ~") : compact;
    }

    function sessionGitChipVisible(session) {
        return sessionGitChipText(session).length > 0;
    }

    function sessionGitChipForeground(session) {
        const state = sessionGitState(session);
        if (state === "conflicted") {
            return colors.textDim;
        }
        if (state === "dirty") {
            return colors.textDim;
        }
        if (Number(session && session.git_snapshot && session.git_snapshot.behind || 0) > 0) {
            return colors.textDim;
        }
        return colors.muted;
    }

    function sessionGitChipBackground(session) {
        const state = sessionGitState(session);
        if (state === "conflicted" || state === "dirty") {
            return Qt.tint(colors.panelAlt, Qt.rgba(0.99, 0.64, 0.69, 0.08));
        }
        if (Number(session && session.git_snapshot && session.git_snapshot.behind || 0) > 0) {
            return Qt.tint(colors.panelAlt, Qt.rgba(0.97, 0.83, 0.55, 0.08));
        }
        return Qt.tint(colors.panelAlt, Qt.rgba(0.53, 0.94, 0.67, 0.06));
    }

    function findWindowById(windowId) {
        const target = Number(windowId || 0);
        if (target <= 0) {
            return null;
        }

        const projects = arrayOrEmpty(dashboard.projects);
        for (let i = 0; i < projects.length; i += 1) {
            const windows = arrayOrEmpty(projects[i].windows);
            for (let j = 0; j < windows.length; j += 1) {
                const windowData = windows[j];
                if (Number(windowData.id || 0) === target) {
                    return windowData;
                }
            }
        }
        return null;
    }

    function workspaceLabel(workspace) {
        return stringOrEmpty(workspace.name || workspace.number || workspace.num);
    }

    function workspaceIconSourcesForWindows(workspaceWindows) {
        const windows = arrayOrEmpty(workspaceWindows).slice().sort(function (left, right) {
            const leftFocused = windowIsFocused(left);
            const rightFocused = windowIsFocused(right);
            if (leftFocused !== rightFocused) {
                return leftFocused ? -1 : 1;
            }

            const leftVisible = boolOrFalse(left && left.visible);
            const rightVisible = boolOrFalse(right && right.visible);
            if (leftVisible !== rightVisible) {
                return leftVisible ? -1 : 1;
            }

            const leftFloating = boolOrFalse(left && left.floating);
            const rightFloating = boolOrFalse(right && right.floating);
            if (leftFloating !== rightFloating) {
                return leftFloating ? 1 : -1;
            }

            return 0;
        });
        const icons = [];

        for (let i = 0; i < windows.length; i += 1) {
            const source = iconSourceFor(windows[i]);
            if (!source || icons.indexOf(source) >= 0) {
                continue;
            }
            icons.push(source);
            if (icons.length >= 2) {
                break;
            }
        }

        return icons;
    }

    function appLabel(windowData) {
        const appName = stringOrEmpty(windowData.app_name || windowData.app_key);
        if (!appName) {
            return "Window";
        }
        if (appName === "terminal") {
            return "Terminal";
        }
        if (appName === "scratchpad-terminal") {
            return "Scratchpad";
        }
        if (appName === "1password") {
            return "1Password";
        }
        return appName;
    }

    function displayTitle(windowData) {
        const title = stringOrEmpty(windowData.title);
        const label = appLabel(windowData);
        if (!title) {
            return label;
        }
        if (title === label || title === "Ghostty") {
            return shortProject(windowData.project);
        }
        return title;
    }

    function displayMeta(windowData) {
        const bits = [];
        const workspace = stringOrEmpty(windowData.workspace);

        if (workspace && workspace.indexOf("scratchpad") !== 0) {
            bits.push("WS " + workspace);
        }

        return bits.join(" • ");
    }

    function iconSourceFor(windowData) {
        const absolute = stringOrEmpty(windowData.icon_path);
        if (absolute) {
            return "file://" + absolute;
        }

        const candidates = [stringOrEmpty(windowData.app_key), stringOrEmpty(windowData.app_name), "application-x-executable"];

        for (let i = 0; i < candidates.length; i += 1) {
            const candidate = candidates[i];
            if (!candidate) {
                continue;
            }
            const resolved = Quickshell.iconPath(candidate, true);
            if (resolved) {
                return resolved;
            }
        }

        return "";
    }

    function launcherEntryAccentColor(entry) {
        const kind = stringOrEmpty(entry && entry.kind);
        const hostTokenData = entry && entry.host_token ? entry.host_token : null;
        if (kind === "session" || kind === "window") {
            return hostTokenData && hostTokenData.is_remote ? colors.orange : colors.blue;
        }
        if (kind === "app") {
            if (launcherEntryHasState(entry, "pwa")) {
                return colors.teal;
            }
            if (launcherEntryHasState(entry, "scoped")) {
                return colors.orange;
            }
            return colors.blueMuted;
        }
        if (kind === "url" || kind === "search") {
            return stringOrEmpty(entry && entry.matched_pwa_ulid) ? colors.teal : colors.blue;
        }
        if (kind === "runner") {
            return colors.orange;
        }
        if (kind === "file") {
            return colors.teal;
        }
        if (kind === "snippet") {
            return colors.teal;
        }
        return "transparent";
    }

    function launcherIconSource(entry) {
        const isApp = stringOrEmpty(entry && entry.kind) === "app";
        const isOnePassword = stringOrEmpty(entry && entry.kind) === "onepassword";
        const isClipboard = stringOrEmpty(entry && entry.kind) === "clipboard";
        const isUrl = stringOrEmpty(entry && entry.kind) === "url" || stringOrEmpty(entry && entry.kind) === "search";
        const isRunner = stringOrEmpty(entry && entry.kind) === "runner";
        const isFile = stringOrEmpty(entry && entry.kind) === "file";
        const isSnippet = stringOrEmpty(entry && entry.kind) === "snippet";
        const icon = stringOrEmpty(entry && entry.icon);
        if (!icon) {
            if (isOnePassword) {
                return Quickshell.iconPath("dialog-password-symbolic", true) || ("file://" + shellConfig.onePasswordIcon);
            }
            if (isClipboard) {
                return Quickshell.iconPath("edit-paste", true) || Quickshell.iconPath("application-x-executable", true) || "";
            }
            if (isUrl) {
                return Quickshell.iconPath("web-browser", true) || Quickshell.iconPath("internet-web-browser", true) || Quickshell.iconPath("application-x-executable", true) || "";
            }
            if (isRunner) {
                return Quickshell.iconPath("utilities-terminal", true) || Quickshell.iconPath("application-x-executable", true) || "";
            }
            if (isFile) {
                if (launcherFileIsDirectory(entry)) {
                    return Quickshell.iconPath("folder", true) || Quickshell.iconPath("folder-open", true) || Quickshell.iconPath("system-file-manager", true) || "";
                }
                return Quickshell.iconPath("text-x-generic", true) || Quickshell.iconPath("application-octet-stream", true) || Quickshell.iconPath("system-file-manager", true) || "";
            }
            if (isSnippet) {
                return Quickshell.iconPath("insert-text", true) || Quickshell.iconPath("application-x-executable", true) || "";
            }
            if (isApp && launcherEntryHasState(entry, "pwa")) {
                return Quickshell.iconPath("internet-web-browser", true) || Quickshell.iconPath("application-x-executable", true) || "";
            }
            return Quickshell.iconPath("application-x-executable", true) || "";
        }

        if (icon.indexOf("/") === 0) {
            return "file://" + icon;
        }

        const resolved = Quickshell.iconPath(icon, true);
        if (resolved) {
            return resolved;
        }

        if (isOnePassword) {
            return Quickshell.iconPath("dialog-password-symbolic", true) || ("file://" + shellConfig.onePasswordIcon);
        }

        if (isClipboard) {
            return Quickshell.iconPath("edit-paste", true) || Quickshell.iconPath("application-x-executable", true) || "";
        }
        if (isUrl) {
            return Quickshell.iconPath("web-browser", true) || Quickshell.iconPath("internet-web-browser", true) || Quickshell.iconPath("application-x-executable", true) || "";
        }
        if (isRunner) {
            return Quickshell.iconPath("utilities-terminal", true) || Quickshell.iconPath("application-x-executable", true) || "";
        }
        if (isFile) {
            if (launcherFileIsDirectory(entry)) {
                return Quickshell.iconPath("folder", true) || Quickshell.iconPath("folder-open", true) || Quickshell.iconPath("system-file-manager", true) || "";
            }
            return Quickshell.iconPath("text-x-generic", true) || Quickshell.iconPath("application-octet-stream", true) || Quickshell.iconPath("system-file-manager", true) || "";
        }
        if (isSnippet) {
            return Quickshell.iconPath("insert-text", true) || Quickshell.iconPath("application-x-executable", true) || "";
        }
        if (isApp && launcherEntryHasState(entry, "pwa")) {
            return Quickshell.iconPath("internet-web-browser", true) || Quickshell.iconPath("application-x-executable", true) || "";
        }

        return Quickshell.iconPath("application-x-executable", true) || "";
    }

    function launcherBadgeColor(tone) {
        const value = stringOrEmpty(tone);
        if (value === "orange") {
            return colors.orange;
        }
        if (value === "teal") {
            return colors.teal;
        }
        if (value === "violet") {
            return colors.violet;
        }
        if (value === "accent") {
            return colors.accent;
        }
        return colors.blue;
    }

    function launcherBadgeBackground(tone) {
        const value = stringOrEmpty(tone);
        if (value === "orange") {
            return colors.orangeBg;
        }
        if (value === "teal") {
            return colors.tealBg;
        }
        if (value === "violet") {
            return colors.violetBg;
        }
        if (value === "accent") {
            return colors.accentBg;
        }
        return colors.blueBg;
    }

    function restartLauncherQuery() {
        if (!launcherVisible) {
            return;
        }

        launcherError = "";

        if (launcherQueryProcess.running) {
            launcherQueryProcess.running = false;
        }

        if (launcherMode === "files") {
            launcherLoading = true;
            launcherQueryProcess.command = [shellConfig.fileListBin, launcherQuery, "40", "20"];
            launcherQueryProcess.running = true;
            return;
        }

        if (launcherMode === "urls") {
            launcherLoading = true;
            launcherQueryProcess.command = [shellConfig.urlListBin, launcherQuery, "30"];
            launcherQueryProcess.running = true;
            return;
        }

        if (launcherMode === "runner") {
            launcherLoading = true;
            launcherQueryProcess.command = [shellConfig.runnerListBin, launcherQuery];
            launcherQueryProcess.running = true;
            return;
        }

        if (launcherMode === "snippets") {
            launcherLoading = true;
            launcherQueryProcess.command = [shellConfig.snippetsListBin, launcherQuery, "40"];
            launcherQueryProcess.running = true;
            return;
        }

        if (launcherMode === "sessions") {
            launcherLoading = false;
            setLauncherEntries(launcherSessionSwitcherActive && launcherQuery === "" ? launcherSessionSwitcherEntries() : launcherSessionEntries(launcherQuery));
            return;
        }

        if (launcherMode === "windows") {
            launcherLoading = false;
            setLauncherEntries(launcherWindowEntries(launcherQuery));
            return;
        }

        if (launcherMode === "onepassword") {
            setLauncherEntries(onePasswordEntries(launcherQuery));
            launcherLoading = onePasswordEntriesCache.length === 0;
            launcherQueryProcess.command = [shellConfig.onePasswordListBin];
            launcherQueryProcess.running = true;
            return;
        }

        if (launcherMode === "clipboard") {
            launcherLoading = true;
            launcherQueryProcess.command = [shellConfig.clipboardListBin, launcherQuery, "30"];
            launcherQueryProcess.running = true;
            return;
        }

        launcherLoading = true;
        launcherQueryProcess.command = [shellConfig.launcherQueryBin, launcherQuery, "20", "20", launcherAppFilter];
        launcherQueryProcess.running = true;
    }

    function parseUrlResults(data) {
        if (launcherMode !== "urls" || !launcherVisible) {
            return;
        }

        const raw = stringOrEmpty(data).trim();
        if (!raw) {
            setLauncherEntries([]);
            launcherLoading = false;
            return;
        }

        try {
            const parsed = JSON.parse(raw);
            setLauncherEntries(Array.isArray(parsed) ? parsed : []);
            launcherLoading = false;
            launcherError = "";
        } catch (error) {
            setLauncherEntries([]);
            launcherLoading = false;
            launcherError = "Unable to load Chrome URL results";
            console.warn("launcher.urls.parse:", raw, error);
        }
    }

    function parseLauncherResults(data) {
        if (launcherMode !== "apps" || !launcherVisible) {
            return;
        }

        const raw = stringOrEmpty(data).trim();
        if (!raw) {
            setLauncherEntries([]);
            launcherLoading = false;
            return;
        }

        try {
            const parsed = JSON.parse(raw);
            setLauncherEntries(Array.isArray(parsed) ? parsed : []);
            launcherLoading = false;
            launcherError = "";
        } catch (error) {
            setLauncherEntries([]);
            launcherLoading = false;
            launcherError = "Unable to load app results";
            console.warn("launcher.query.parse:", raw, error);
        }
    }

    function parseFileResults(data) {
        if (launcherMode !== "files" || !launcherVisible) {
            return;
        }

        const raw = stringOrEmpty(data).trim();
        if (!raw) {
            setLauncherEntries([]);
            launcherLoading = false;
            return;
        }

        try {
            const parsed = JSON.parse(raw);
            setLauncherEntries(Array.isArray(parsed) ? parsed : []);
            launcherLoading = false;
            launcherError = "";
        } catch (error) {
            setLauncherEntries([]);
            launcherLoading = false;
            launcherError = "Unable to load file results";
            console.warn("launcher.files.parse:", raw, error);
        }
    }

    function parseRunnerResults(data) {
        if (launcherMode !== "runner" || !launcherVisible) {
            return;
        }

        const raw = stringOrEmpty(data).trim();
        if (!raw) {
            setLauncherEntries([]);
            launcherLoading = false;
            return;
        }

        try {
            const parsed = JSON.parse(raw);
            setLauncherEntries(Array.isArray(parsed) ? parsed : []);
            launcherLoading = false;
            launcherError = "";
        } catch (error) {
            setLauncherEntries([]);
            launcherLoading = false;
            launcherError = "Unable to prepare command";
            console.warn("launcher.runner.parse:", raw, error);
        }
    }

    function parseSnippetResults(data) {
        if (launcherMode !== "snippets" || !launcherVisible) {
            return;
        }

        const raw = stringOrEmpty(data).trim();
        if (!raw) {
            setLauncherEntries([]);
            launcherLoading = false;
            return;
        }

        try {
            const parsed = JSON.parse(raw);
            setLauncherEntries(Array.isArray(parsed) ? parsed : []);
            launcherLoading = false;
            launcherError = "";
        } catch (error) {
            setLauncherEntries([]);
            launcherLoading = false;
            launcherError = "Unable to load curated commands";
            console.warn("launcher.snippets.parse:", raw, error);
        }
    }

    function parseOnePasswordResults(data) {
        if (launcherMode !== "onepassword" || !launcherVisible) {
            return;
        }

        const raw = stringOrEmpty(data).trim();
        if (!raw) {
            onePasswordEntriesCache = [];
            setLauncherEntries([]);
            launcherLoading = false;
            return;
        }

        try {
            const parsed = JSON.parse(raw);
            onePasswordEntriesCache = Array.isArray(parsed) ? parsed : [];
            setLauncherEntries(onePasswordEntries(launcherQuery));
            launcherLoading = false;
            launcherError = "";
        } catch (error) {
            onePasswordEntriesCache = [];
            setLauncherEntries([]);
            launcherLoading = false;
            launcherError = "Unable to load 1Password items";
            console.warn("launcher.onepassword.parse:", raw, error);
        }
    }

    function parseClipboardResults(data) {
        if (launcherMode !== "clipboard" || !launcherVisible) {
            return;
        }

        const raw = stringOrEmpty(data).trim();
        if (!raw) {
            setLauncherEntries([]);
            launcherLoading = false;
            return;
        }

        try {
            const parsed = JSON.parse(raw);
            setLauncherEntries(Array.isArray(parsed) ? parsed : []);
            launcherLoading = false;
            launcherError = "";
        } catch (error) {
            setLauncherEntries([]);
            launcherLoading = false;
            launcherError = "Unable to load clipboard history";
            console.warn("launcher.clipboard.parse:", raw, error);
        }
    }

    function activeLauncherEntry() {
        const entries = arrayOrEmpty(launcherEntries);
        if (!entries.length) {
            return null;
        }
        if (launcherSelectedIndex < 0 || launcherSelectedIndex >= entries.length) {
            return entries[0];
        }
        return entries[launcherSelectedIndex];
    }

    function moveLauncherSelection(delta) {
        const entries = arrayOrEmpty(launcherEntries);
        if (!entries.length) {
            launcherSelectedIndex = 0;
            return;
        }

        launcherPointerSelectionEnabled = false;
        launcherSelectionMode = "keyboard";
        launcherViewportPrimed = true;
        launcherSelectedIndex = (launcherSelectedIndex + delta + entries.length) % entries.length;
    }

    function updateLauncherPointerSelection(index) {
        const entryIndex = Number(index);
        if (isNaN(entryIndex) || entryIndex < 0 || entryIndex >= launcherEntries.length) {
            return;
        }

        launcherPointerSelectionEnabled = true;
        launcherSelectionMode = "pointer";
        launcherViewportPrimed = true;
        if (launcherSelectedIndex !== entryIndex) {
            launcherSelectedIndex = entryIndex;
        }
    }

    function syncLauncherListSelection() {
        if (!launcherVisible) {
            return;
        }

        const entries = arrayOrEmpty(launcherEntries);
        if (!entries.length || launcherSelectedIndex < 0) {
            if (launcherList) {
                launcherList.currentIndex = -1;
            }
            return;
        }

        const nextIndex = Math.max(0, Math.min(launcherSelectedIndex, entries.length - 1));
        if (!launcherList) {
            return;
        }

        launcherList.currentIndex = nextIndex;
        Qt.callLater(function() {
            if (!launcherVisible || !launcherList) {
                return;
            }

            const latestEntries = root.arrayOrEmpty(root.launcherEntries);
            if (!latestEntries.length || root.launcherSelectedIndex !== nextIndex || nextIndex >= latestEntries.length) {
                return;
            }

            launcherList.currentIndex = nextIndex;
            if (root.launcherSelectionMode === "initial" && root.stringOrEmpty(root.launcherQuery) === "" && nextIndex === 0) {
                launcherList.positionViewAtBeginning();
                root.launcherViewportPrimed = true;
                return;
            }

            launcherList.positionViewAtIndex(nextIndex, ListView.Contain);
            root.launcherViewportPrimed = true;
        });
    }

    function resetLauncherListViewport() {
        if (!launcherList) {
            return;
        }

        launcherList.currentIndex = -1;
        launcherViewportPrimed = false;
        Qt.callLater(function() {
            if (!launcherList) {
                return;
            }
            launcherList.positionViewAtBeginning();
        });
    }

    function closeLauncher() {
        launcherVisible = false;
    }

    function activateLauncherEntry(entry, actionMode) {
        const kind = stringOrEmpty(entry && entry.kind);
        if (kind === "global") {
            closeLauncher();
            clearContext();
            return;
        }
        if (kind === "project") {
            closeLauncher();
            activateWorktree(entry, stringOrEmpty(entry && entry.target_host));
            return;
        }
        if (kind === "session") {
            const sessionKey = stringOrEmpty(entry && entry.session_key);
            if (!sessionKey) {
                return;
            }

            closeLauncher();
            focusSession(entry);
            return;
        }
        if (kind === "window") {
            closeLauncher();
            if (stringOrEmpty(actionMode) === "close") {
                closeWindow(entry);
            } else {
                focusWindow(entry);
            }
            return;
        }
        if (kind === "onepassword") {
            const itemId = stringOrEmpty(entry && entry.identifier);
            const mode = stringOrEmpty(actionMode || "password") || "password";
            if (!itemId) {
                return;
            }

            closeLauncher();
            runDetached([shellConfig.onePasswordActionBin, mode, itemId]);
            return;
        }
        if (kind === "clipboard") {
            const identifier = stringOrEmpty(entry && entry.identifier);
            const action = stringOrEmpty(actionMode || "copy") || "copy";
            if (!identifier) {
                return;
            }

            closeLauncher();
            runDetached([shellConfig.clipboardActionBin, action, identifier]);
            return;
        }
        if (kind === "file") {
            const identifier = stringOrEmpty(entry && entry.identifier);
            const action = stringOrEmpty(actionMode || "open") || "open";
            if (!identifier) {
                return;
            }

            closeLauncher();
            runDetached([shellConfig.fileActionBin, action, identifier]);
            return;
        }
        if (kind === "url" || kind === "search") {
            const url = stringOrEmpty(entry && entry.url);
            const mode = stringOrEmpty(actionMode || "preferred") || "preferred";
            if (!url) {
                return;
            }

            closeLauncher();
            runDetached([shellConfig.urlOpenBin, mode, url]);
            return;
        }
        if (kind === "runner") {
            const command = stringOrEmpty(entry && (entry.command || entry.text || entry.identifier));
            const mode = stringOrEmpty(actionMode || "background") || "background";
            if (!command) {
                return;
            }

            closeLauncher();
            runDetached([shellConfig.launcherCommandActionBin, mode, command]);
            return;
        }
        if (kind === "snippet") {
            const command = stringOrEmpty(entry && (entry.command || entry.identifier || entry.text));
            const mode = stringOrEmpty(actionMode || "background") || "background";
            if (!command) {
                return;
            }

            closeLauncher();
            runDetached([shellConfig.launcherCommandActionBin, mode, command]);
            return;
        }

        const identifier = stringOrEmpty(entry && entry.identifier);
        if (!identifier) {
            return;
        }

        closeLauncher();
        runDetached([shellConfig.launcherLaunchBin, identifier]);
    }

    function activateSelectedLauncherEntry(actionMode) {
        activateLauncherEntry(activeLauncherEntry(), actionMode);
    }

    function runDetached(command) {
        if (!command || !command.length) {
            return;
        }
        Quickshell.execDetached(command);
    }

    function showRuntimePanel(outputName) {
        // Pin the panel to the monitor that requested it (bar button click).
        // When empty (keybinding/IPC, no monitor context) the panel falls back
        // to root.activeScreen via RuntimePanelWindow's screen binding.
        panelOutputName = stringOrEmpty(outputName);
        panelVisible = true;
        panelSection = "runtime";
        worktreePickerVisible = false;
        audioPopupVisible = false;
        bluetoothPopupVisible = false;
        displaySelectorVisible = false;
        ensureRuntimePanelExpandedSection();
    }

    function focusSession(sessionKey) {
        const sessionData = (typeof sessionKey === "object") ? sessionKey : null;
        const resolvedSessionKey = stringOrEmpty(sessionData && sessionData.session_key) || stringOrEmpty(sessionKey);
        if (!resolvedSessionKey) {
            return;
        }

        const current = currentSessionKey();
        if (current && current !== resolvedSessionKey) {
            lastFocusedSessionKey = current;
        }

        const target = sessionFocusTarget(sessionData || resolvedSessionKey);
        runFocusTarget(target);
    }

    function sessionByKey(sessionKey) {
        const key = stringOrEmpty(sessionKey);
        if (!key) {
            return null;
        }
        const sessions = activeSessions();
        for (let i = 0; i < sessions.length; i += 1) {
            const session = sessions[i];
            if (sessionMatchesKey(session, key)) {
                return session;
            }
        }
        return null;
    }

    function cycleSessions(direction) {
        const sessions = panelSessions();
        if (!sessions.length) {
            return;
        }

        const current = currentSessionKey();
        let index = sessions.findIndex(item => stringOrEmpty(item.session_key) === current);
        if (index < 0) {
            index = 0;
        }

        const delta = direction === "prev" ? -1 : 1;
        const nextIndex = (index + delta + sessions.length) % sessions.length;
        focusSession(sessions[nextIndex]);
    }

    function cycleLauncherSessions(direction) {
        const delta = direction === "prev" ? -1 : 1;
        const shouldOpenSwitcher = !launcherVisible || launcherMode !== "sessions" || launcherQuery !== "" || !launcherSessionSwitcherActive;
        if (shouldOpenSwitcher) {
            launcherSessionSwitcherActive = true;
            launcherSessionSwitcherPendingDelta = delta;
            showLauncher("sessions", "");
            launcherSessionSwitcherOpenTimer.restart();
            return;
        }

        launcherSessionSwitcherPendingDelta = 0;
        moveLauncherSelection(delta);
        launcherFocusTimer.restart();
    }

    function finalizeLauncherSessionSwitcherOpen() {
        if (!launcherVisible || launcherMode !== "sessions" || launcherSessionSwitcherPendingDelta === 0) {
            return;
        }

        const delta = launcherSessionSwitcherPendingDelta;
        launcherSessionSwitcherPendingDelta = 0;
        const entries = launcherSessionSwitcherEntries();
        setLauncherEntries(entries);
        if (!entries.length) {
            return;
        }

        const current = currentSessionKey();
        let index = entries.findIndex(item => stringOrEmpty(item.session_key) === current);
        if (index < 0) {
            index = 0;
        }

        launcherPointerSelectionEnabled = false;
        launcherSelectionMode = "keyboard";
        launcherViewportPrimed = true;
        launcherSelectedIndex = (index + delta + entries.length) % entries.length;
    }

    function commitLauncherSessionSwitch() {
        if (!launcherVisible || launcherMode !== "sessions" || !launcherSessionSwitcherActive) {
            return;
        }

        const entry = activeLauncherSessionEntry();
        launcherSessionSwitcherActive = false;
        launcherSessionSwitcherPendingDelta = 0;
        if (!entry) {
            closeLauncher();
            return;
        }

        activateLauncherEntry(entry);
    }

    function cycleLauncherWindows(direction) {
        const delta = direction === "prev" ? -1 : 1;
        const shouldOpenSwitcher = !launcherVisible || launcherMode !== "windows" || launcherQuery !== "" || !launcherWindowSwitcherActive;
        if (shouldOpenSwitcher) {
            launcherWindowSwitcherActive = true;
            launcherWindowSwitcherPendingDelta = delta;
            showLauncher("windows", "");
            launcherWindowSwitcherOpenTimer.restart();
            return;
        }

        launcherWindowSwitcherPendingDelta = 0;
        moveLauncherSelection(delta);
        launcherFocusTimer.restart();
    }

    function finalizeLauncherWindowSwitcherOpen() {
        if (!launcherVisible || launcherMode !== "windows" || launcherWindowSwitcherPendingDelta === 0) {
            return;
        }

        const delta = launcherWindowSwitcherPendingDelta;
        launcherWindowSwitcherPendingDelta = 0;
        const entries = launcherWindowSwitcherEntries();
        setLauncherEntries(entries);
        if (!entries.length) {
            return;
        }

        launcherPointerSelectionEnabled = false;
        launcherSelectionMode = "keyboard";
        launcherViewportPrimed = true;
        launcherSelectedIndex = delta < 0 ? entries.length - 1 : 0;
    }

    function commitLauncherWindowSwitch() {
        if (!launcherVisible || launcherMode !== "windows" || !launcherWindowSwitcherActive) {
            return;
        }

        const entry = activeLauncherEntry();
        launcherWindowSwitcherActive = false;
        launcherWindowSwitcherPendingDelta = 0;
        if (!entry) {
            closeLauncher();
            return;
        }

        activateLauncherEntry(entry);
    }

    // ===== Full-screen window-switcher exposé =====
    // Like launcherWindowProjects but INCLUDES the focused window (tagged so the
    // grid can draw a "current" ring); the exposé is a full overview, not a
    // next-only Alt+Tab list.
    function exposeWindowProjects(query) {
        const tokens = launcherQueryTokens(query);
        const allProjects = arrayOrEmpty(dashboard.projects);
        const projects = [];
        for (let p = 0; p < allProjects.length; p += 1) {
            const projectGroup = allProjects[p];
            const windows = arrayOrEmpty(projectGroup && projectGroup.windows);
            if (!windows.length) {
                continue;
            }
            projects.push(Object.assign({}, projectGroup, { windows: windows }));
        }
        if (!tokens.length) {
            return projects;
        }
        const filtered = [];
        for (let i = 0; i < projects.length; i += 1) {
            const projectGroup = projects[i];
            const matched = arrayOrEmpty(projectGroup && projectGroup.windows).filter(function (windowData) {
                return launcherWindowMatches(windowData, tokens);
            });
            if (!matched.length) {
                continue;
            }
            filtered.push(Object.assign({}, projectGroup, { windows: matched }));
        }
        return filtered;
    }

    function exposeWindowEntries(query) {
        const entries = [];
        const projects = exposeWindowProjects(query);
        for (let i = 0; i < projects.length; i += 1) {
            const windows = arrayOrEmpty(projects[i] && projects[i].windows);
            for (let j = 0; j < windows.length; j += 1) {
                const windowData = windows[j];
                entries.push(Object.assign({}, windowData, {
                    kind: "window",
                    identifier: String(Number(windowData && (windowData.id || windowData.window_id) || 0)),
                    text: displayTitle(windowData),
                    subtext: displayMeta(windowData),
                    host_token: windowHostToken(windowData),
                    focused: windowIsFocused(windowData)
                }));
            }
        }
        return entries;
    }

    // herdr agent sessions (local + remote) surfaced in the exposé as a synthetic
    // "AI Agents" panel. Each entry is the raw session plus the fields the exposé
    // grouping/selection/match expect; SessionRow renders it from the raw session.
    function exposeAgentEntries(query) {
        const sessions = activeSessions();
        const tokens = launcherQueryTokens(stringOrEmpty(query));
        const out = [];
        for (let i = 0; i < sessions.length; i += 1) {
            const s = sessions[i];
            if (!s) {
                continue;
            }
            const title = sessionPrimaryLabel(s);
            const sub = sessionSecondaryLabel(s);
            if (tokens.length) {
                const hay = (title + " " + sub + " " + stringOrEmpty(s.agent) + " "
                    + stringOrEmpty(s.display_tool) + " " + stringOrEmpty(s.project)).toLowerCase();
                let ok = true;
                for (let t = 0; t < tokens.length; t += 1) {
                    if (hay.indexOf(tokens[t]) < 0) {
                        ok = false;
                        break;
                    }
                }
                if (!ok) {
                    continue;
                }
            }
            out.push(Object.assign({}, s, {
                kind: "session",
                output: exposeAgentsOutput,
                title: title,
                app_name: stringOrEmpty(s.agent),
                focused: sessionIsCurrent(s)
            }));
        }
        return out;
    }

    function refreshExposeEntries() {
        const raw = normalizeLauncherEntries(exposeWindowEntries(stringOrEmpty(exposeQuery)))
            .concat(exposeAgentEntries(stringOrEmpty(exposeQuery)));
        const tokens = launcherQueryTokens(stringOrEmpty(exposeQuery));
        const hasQuery = tokens.length > 0;
        // Stable daemon order is the final tiebreak.
        for (let i = 0; i < raw.length; i += 1) {
            raw[i]._do = i;
        }
        // Group by monitor (physical left-to-right) so panels, Tab order and arrow
        // nav line up. Within each monitor: focused-first, then search-match score
        // (when filtering) or MRU recency, then the daemon's stable order. Each
        // entry gets a global index (_gi) used for selection.
        const panels = exposePanelOutputsFromEntries(raw);
        const grouped = [];
        for (let p = 0; p < panels.length; p += 1) {
            const inPanel = raw.filter(function (e) {
                return (stringOrEmpty(e.output) || "?") === panels[p];
            });
            inPanel.sort(function (a, b) {
                const fa = a.focused ? 1 : 0;
                const fb = b.focused ? 1 : 0;
                if (fa !== fb) {
                    return fb - fa;
                }
                if (hasQuery) {
                    const sa = exposeMatchScore(a, tokens);
                    const sb = exposeMatchScore(b, tokens);
                    if (sa !== sb) {
                        return sb - sa;
                    }
                } else {
                    const ra = Number(exposeRecency[windowIdValue(a)] || 0);
                    const rb = Number(exposeRecency[windowIdValue(b)] || 0);
                    if (ra !== rb) {
                        return rb - ra;
                    }
                }
                return a._do - b._do;
            });
            for (let i = 0; i < inPanel.length; i += 1) {
                grouped.push(inPanel[i]);
            }
        }
        for (let i = 0; i < grouped.length; i += 1) {
            grouped[i]._gi = i;
        }
        exposeEntries = grouped;
        // Prune recency only when showing the full set (no filter), so windows
        // hidden by a query don't lose their recency stamp.
        if (!hasQuery) {
            pruneExposeRecency(grouped);
        }
        if (exposeSelectedIndex >= grouped.length) {
            exposeSelectedIndex = Math.max(0, grouped.length - 1);
        }
    }

    // Search relevance for the exposé filter: title-prefix > title-substring >
    // app name/key > project/workspace/output.
    function exposeMatchScore(entry, tokens) {
        if (!tokens || !tokens.length) {
            return 0;
        }
        const title = stringOrEmpty(entry && entry.title).toLowerCase();
        const app = (stringOrEmpty(entry && entry.app_name) + " " + stringOrEmpty(entry && entry.app_key)).toLowerCase();
        const ctx = (stringOrEmpty(entry && entry.project) + " " + stringOrEmpty(entry && entry.workspace) + " " + stringOrEmpty(entry && entry.output)).toLowerCase();
        let score = 0;
        for (let i = 0; i < tokens.length; i += 1) {
            const t = stringOrEmpty(tokens[i]);
            if (!t) {
                continue;
            }
            if (title.indexOf(t) === 0) {
                score += 100;
            } else if (title.indexOf(t) >= 0) {
                score += 60;
            } else if (app.indexOf(t) >= 0) {
                score += 40;
            } else if (ctx.indexOf(t) >= 0) {
                score += 20;
            }
        }
        return score;
    }

    // Drop recency stamps for windows that no longer exist (called with the full
    // window set so live windows aren't pruned).
    function pruneExposeRecency(entries) {
        const live = {};
        for (let i = 0; i < entries.length; i += 1) {
            const id = windowIdValue(entries[i]);
            if (id) {
                live[id] = true;
            }
        }
        const m = exposeRecency;
        for (const k in m) {
            if (!live[k]) {
                delete m[k];
            }
        }
    }

    // "N windows · M agents" summary for the exposé header.
    function exposeSummaryText() {
        const entries = arrayOrEmpty(exposeEntries);
        let w = 0, a = 0;
        for (let i = 0; i < entries.length; i += 1) {
            if (stringOrEmpty(entries[i].kind) === "session") {
                a += 1;
            } else {
                w += 1;
            }
        }
        const parts = [w + (w === 1 ? " window" : " windows")];
        if (a > 0) {
            parts.push(a + (a === 1 ? " agent" : " agents"));
        }
        return parts.join("  ·  ");
    }

    // Distinct monitor names present in a set of window entries, ordered by the
    // monitor's physical x position (left-to-right).
    function exposePanelOutputsFromEntries(entries) {
        const seen = {};
        const list = [];
        const es = arrayOrEmpty(entries);
        for (let i = 0; i < es.length; i += 1) {
            const o = stringOrEmpty(es[i].output) || "?";
            if (!seen[o]) {
                seen[o] = true;
                list.push(o);
            }
        }
        const xmap = exposeOutputX || {};
        // The synthetic "AI Agents" panel sorts to the far left; real monitors
        // order by physical x position.
        list.sort(function (a, b) {
            const xa = (a === exposeAgentsOutput) ? -1 : ((a in xmap) ? Number(xmap[a]) : 99999);
            const xb = (b === exposeAgentsOutput) ? -1 : ((b in xmap) ? Number(xmap[b]) : 99999);
            return xa - xb;
        });
        return list;
    }

    // Live monitor x-positions (name -> logical x), filled from `swaymsg -t
    // get_outputs` when the exposé opens. The daemon dashboard geometry is stale,
    // so we read sway directly to order the panels left-to-right correctly.
    property var exposeOutputX: ({})

    function parseExposeOutputX(jsonText) {
        try {
            const arr = JSON.parse(stringOrEmpty(jsonText));
            const m = {};
            let focusedName = "";
            for (let i = 0; i < arr.length; i += 1) {
                const o = arr[i];
                if (o && o.active && o.rect) {
                    m[stringOrEmpty(o.name)] = Number(o.rect.x || 0);
                    if (o.focused) {
                        focusedName = stringOrEmpty(o.name);
                    }
                }
            }
            exposeOutputX = m;
            // Pin the overlay to the LIVE focused output (sway is authoritative;
            // I3.focusedMonitor can be stale, which lands the exposé on the wrong
            // monitor). Only override when we resolved a real screen for it.
            if (exposeVisible && focusedName && findScreenByOutputName(focusedName)) {
                exposeOutputName = focusedName;
                const fIdx = exposeFocusedIndex();
                if (fIdx < 0) {
                    exposeSelectedIndex = exposeFirstIndexForOutput(focusedName);
                }
            }
            if (exposeVisible) {
                refreshExposeEntries();
            }
        } catch (e) {
            // leave the previous map in place
        }
    }

    function exposePanelOutputs() {
        return exposePanelOutputsFromEntries(exposeEntries);
    }

    function exposeWindowsForOutput(name) {
        const n = stringOrEmpty(name);
        return arrayOrEmpty(exposeEntries).filter(function (e) {
            return (stringOrEmpty(e.output) || "?") === n;
        });
    }

    // Monitors a window could be moved TO (every active monitor except its own).
    function exposeMoveTargets(entry) {
        const cur = stringOrEmpty(entry && entry.output) || "?";
        const all = exposeOutputs();
        return all.filter(function (o) { return o !== cur; });
    }

    function exposeFocusedIndex() {
        const entries = arrayOrEmpty(exposeEntries);
        for (let i = 0; i < entries.length; i += 1) {
            if (entries[i] && entries[i].focused) {
                return i;
            }
        }
        return -1;
    }

    // Lowest global selection index (_gi) of a window on the given output, so the
    // exposé pre-selects a tile on the monitor where it was activated. Falls back
    // to 0 when that output has no windows.
    function exposeFirstIndexForOutput(name) {
        const wins = exposeWindowsForOutput(name);
        if (wins.length && typeof wins[0]._gi === "number") {
            return wins[0]._gi;
        }
        return 0;
    }

    // Alt+Tab path: open (held) and pre-select the next window relative to the
    // focused one; further taps advance; Alt-release commits.
    function cycleExposeWindows(direction) {
        const delta = direction === "prev" ? -1 : 1;
        if (!exposeVisible) {
            exposeOutputName = focusedOutputName();
            exposeSwitcherActive = true;
            exposePendingDelta = delta;
            exposeQuery = "";
            exposeVisible = true;
            if (exposeOpenTimer) {
                exposeOpenTimer.restart();
            }
            if (exposeFocusTimer) {
                exposeFocusTimer.restart();
            }
            return;
        }
        exposePendingDelta = 0;
        cycleExposeSelection(delta);
        if (exposeFocusTimer) {
            exposeFocusTimer.restart();
        }
    }

    function finalizeExposeOpen() {
        if (!exposeVisible || exposePendingDelta === 0) {
            return;
        }
        const delta = exposePendingDelta;
        exposePendingDelta = 0;
        refreshExposeEntries();
        const entries = arrayOrEmpty(exposeEntries);
        if (!entries.length) {
            return;
        }
        const focusedIdx = exposeFocusedIndex();
        if (focusedIdx < 0) {
            exposeSelectedIndex = delta < 0 ? entries.length - 1 : 0;
        } else {
            exposeSelectedIndex = (focusedIdx + delta + entries.length) % entries.length;
        }
    }

    // One-shot path (3-finger swipe): open and stay until click/Enter/Esc.
    // Minimalist agent-monitor side strip toggle. Captures the focused output so
    // it appears on the monitor you're watching (e.g. the TV's Samsung).
    function toggleAgentMonitor(outputName) {
        if (agentMonitorVisible) {
            agentMonitorVisible = false;
            return;
        }
        agentMonitorOutputName = stringOrEmpty(outputName) || focusedOutputName();
        agentMonitorVisible = true;
    }

    function closeAgentMonitor() {
        agentMonitorVisible = false;
    }

    // Gesture-toggle: the same 3-finger swipe-up that opens the exposé also
    // dismisses it. Decided here in QML where exposeVisible is authoritative, so
    // the sway-exec'd wrapper needs no overlay-state getter.
    function toggleExpose() {
        if (exposeVisible) {
            if (Date.now() - exposeOpenedAtMs < exposeReopenGuardMs) {
                return; // ignore an open-bounce double swipe
            }
            closeExpose();
            return;
        }
        openExpose();
    }

    function openExpose() {
        exposeOutputName = focusedOutputName();
        exposeSwitcherActive = false;
        exposePendingDelta = 0;
        exposeQuery = "";
        exposeVisible = true;
        exposeOpenedAtMs = Date.now();
        refreshExposeEntries();
        const focusedIdx = exposeFocusedIndex();
        // Pre-select the focused window if any; otherwise a tile on the monitor
        // where the exposé was activated.
        exposeSelectedIndex = focusedIdx >= 0 ? focusedIdx : exposeFirstIndexForOutput(exposeOutputName);
        if (exposeFocusTimer) {
            exposeFocusTimer.restart();
        }
    }

    function cycleExposeSelection(delta) {
        const entries = arrayOrEmpty(exposeEntries);
        if (!entries.length) {
            exposeSelectedIndex = 0;
            return;
        }
        exposeSelectedIndex = (exposeSelectedIndex + delta + entries.length) % entries.length;
    }

    // Grouped-by-monitor nav: Up/Down move within the current monitor's window
    // list; Left/Right jump to the adjacent monitor (keeping the vertical slot).
    function moveExposeSelectionSpatial(dir) {
        const entries = arrayOrEmpty(exposeEntries);
        if (!entries.length) {
            return;
        }
        const panels = exposePanelOutputs();
        const sel = exposeSelectedIndex;
        const curOut = (sel >= 0 && sel < entries.length)
            ? (stringOrEmpty(entries[sel].output) || "?")
            : (panels.length ? panels[0] : "?");
        const outIdx = Math.max(0, panels.indexOf(curOut));
        const wins = exposeWindowsForOutput(curOut);
        let winIdx = 0;
        for (let i = 0; i < wins.length; i += 1) {
            if (wins[i]._gi === sel) {
                winIdx = i;
                break;
            }
        }
        if (dir === "up" || dir === "down") {
            let wi = winIdx + (dir === "down" ? 1 : -1);
            wi = Math.max(0, Math.min(wins.length - 1, wi));
            if (wins.length) {
                exposeSelectedIndex = wins[wi]._gi;
            }
        } else {
            let oi = outIdx + (dir === "right" ? 1 : -1);
            oi = Math.max(0, Math.min(panels.length - 1, oi));
            const w2 = exposeWindowsForOutput(panels[oi]);
            if (w2.length) {
                const wi = Math.max(0, Math.min(w2.length - 1, winIdx));
                exposeSelectedIndex = w2[wi]._gi;
            }
        }
    }

    function updateExposePointerSelection(index) {
        const entryIndex = Number(index);
        if (isNaN(entryIndex) || entryIndex < 0 || entryIndex >= arrayOrEmpty(exposeEntries).length) {
            return;
        }
        if (exposeSelectedIndex !== entryIndex) {
            exposeSelectedIndex = entryIndex;
        }
    }

    function activeExposeEntry() {
        const entries = arrayOrEmpty(exposeEntries);
        if (!entries.length) {
            return null;
        }
        if (exposeSelectedIndex >= 0 && exposeSelectedIndex < entries.length) {
            return entries[exposeSelectedIndex];
        }
        return entries[0];
    }

    function activateExposeSelection() {
        const entry = activeExposeEntry();
        closeExpose();
        exposeActivateEntry(entry);
    }

    // Activate an exposé entry: agent sessions focus their herdr pane, windows
    // focus the window.
    function exposeActivateEntry(entry) {
        if (!entry) {
            return;
        }
        if (stringOrEmpty(entry.kind) === "session") {
            focusSession(entry);
        } else {
            focusWindow(entry);
        }
    }

    function commitExposeSwitch() {
        if (!exposeVisible || !exposeSwitcherActive) {
            return;
        }
        const entry = activeExposeEntry();
        exposeSwitcherActive = false;
        exposePendingDelta = 0;
        closeExpose();
        exposeActivateEntry(entry);
    }

    function closeExposeWindowEntry(entry) {
        if (entry) {
            closeWindow(entry);
        }
        Qt.callLater(refreshExposeEntries);
    }

    function closeExpose() {
        exposeVisible = false;
        exposeSwitcherActive = false;
        exposePendingDelta = 0;
        exposeQuery = "";
    }

    // ----- Per-window monitor display + move-to-output (exposé) -----
    // Active output (monitor) names, from the daemon dashboard snapshot.
    function exposeOutputs() {
        const outs = arrayOrEmpty(dashboard.outputs);
        const names = [];
        for (let i = 0; i < outs.length; i += 1) {
            const o = outs[i];
            if (o && o.active !== false) {
                const n = stringOrEmpty(o.name);
                if (n && names.indexOf(n) === -1) {
                    names.push(n);
                }
            }
        }
        return names;
    }

    // Friendly short label for a monitor chip.
    function exposeOutputLabel(name) {
        const n = stringOrEmpty(name);
        if (n === exposeAgentsOutput) {
            return "AI Agents";
        }
        if (n === "eDP-1") {
            return "Laptop";
        }
        return n;
    }

    // Agents panel gets a terminal glyph; laptop a laptop glyph; else a monitor.
    function exposeOutputGlyph(name) {
        const n = stringOrEmpty(name);
        if (n === exposeAgentsOutput) {
            return "";
        }
        return n === "eDP-1" ? "" : "";
    }

    function exposeEntryIsRemote(entry) {
        const ht = entry && entry.host_token ? entry.host_token : null;
        if (ht && ht.is_remote) {
            return true;
        }
        return stringOrEmpty(entry && entry.execution_mode) === "ssh";
    }

    // Move a window's WHOLE WORKSPACE to a monitor, so the workspace number
    // travels with it and the window fills the destination — rather than
    // detaching the window onto the destination's current workspace. entry.id is
    // the Sway con_id (the daemon's window actions address windows as
    // [con_id=<id>]). Focus the window first so `move workspace to output` acts
    // on its workspace. Refresh the grid shortly after so badges update.
    function moveExposeWindowToOutput(entry, outputName) {
        const id = Number(entry && (entry.id || entry.window_id) || 0);
        const out = stringOrEmpty(outputName);
        if (!id || !out || exposeEntryIsRemote(entry)) {
            return;
        }
        if (stringOrEmpty(entry.output) === out) {
            return;
        }
        runDetached(["swaymsg", "[con_id=" + id + "] focus; move workspace to output " + out]);
        if (exposeRefreshTimer) {
            exposeRefreshTimer.restart();
        }
    }

    function focusLastSession() {
        if (lastFocusedSessionKey) {
            focusSession(lastFocusedSessionKey);
            return;
        }

        const sessions = panelSessions();
        if (sessions.length) {
            focusSession(sessions[0]);
        }
    }

    function plainJsonValue(value) {
        if (value === null || value === undefined) {
            return null;
        }

        if (Array.isArray(value)) {
            const items = [];
            for (let i = 0; i < value.length; i += 1) {
                items.push(plainJsonValue(value[i]));
            }
            return items;
        }

        if (typeof value === "object") {
            const plain = {};
            for (const key in value) {
                if (!Object.prototype.hasOwnProperty.call(value, key)) {
                    continue;
                }
                plain[String(key)] = plainJsonValue(value[key]);
            }
            return plain;
        }

        return value;
    }

    function normalizedFocusTarget(target) {
        if (!target) {
            return null;
        }

        const method = stringOrEmpty(target.method);
        if (!method) {
            return null;
        }

        return {
            method: method,
            params: plainJsonValue(target.params || {}) || {},
        };
    }

    function runDaemonCall(method, params) {
        const normalizedMethod = stringOrEmpty(method);
        if (!normalizedMethod) {
            return;
        }

        const command = [shellConfig.i3pmBin, "daemon", "call", normalizedMethod];
        const serializedParams = JSON.stringify(plainJsonValue(params || {}) || {});
        if (serializedParams) {
            command.push("--params-json", serializedParams);
        }
        command.push("--json");
        runDetached(command);
    }

    function runDaemonSocketCall(method, params) {
        const normalizedMethod = stringOrEmpty(method);
        if (!normalizedMethod || !runtimeServices || typeof runtimeServices.sendDaemonAction !== "function") {
            console.warn("daemon.action: bridge unavailable for", normalizedMethod || "<missing method>");
            return false;
        }
        const sent = runtimeServices.sendDaemonAction(normalizedMethod, plainJsonValue(params || {}) || {});
        if (!sent) {
            console.warn("daemon.action: bridge rejected", normalizedMethod);
        }
        return sent;
    }

    function runDaemonAction(method, params) {
        if (!runDaemonSocketCall(method, params)) {
            localFocusIntent = null;
        }
    }

    function runFocusTarget(target) {
        const normalizedTarget = normalizedFocusTarget(target);
        if (!normalizedTarget) {
            return;
        }

        beginLocalFocusIntent(normalizedTarget.method, normalizedTarget.params);
        runDaemonAction(normalizedTarget.method, normalizedTarget.params);
    }

    function sessionFocusTarget(sessionOrKey) {
        if (sessionOrKey && typeof sessionOrKey === "object") {
            const explicitTarget = normalizedFocusTarget(sessionOrKey.focus_target);
            return explicitTarget;
        }

        const session = sessionByKey(sessionOrKey);
        return session ? normalizedFocusTarget(session.focus_target) : null;
    }

    function windowFocusTarget(windowData) {
        if (!windowData) {
            return null;
        }

        const explicitTarget = normalizedFocusTarget(windowData.focus_target);
        if (explicitTarget && !windowFastFocusEligible(windowData)) {
            return explicitTarget;
        }

        const windowId = windowIdValue(windowData);
        if (!windowId) {
            return null;
        }

        if (windowFastFocusEligible(windowData)) {
            return {
                method: "window.focus_fast",
                params: {
                    window_id: windowId,
                    project_name: stringOrEmpty(windowData.project),
                    target_variant: stringOrEmpty(windowData.execution_mode),
                    connection_key: stringOrEmpty(windowData.connection_key),
                    session_key: stringOrEmpty(windowData.session_key),
                },
            };
        }

        if (explicitTarget) {
            return explicitTarget;
        }

        return {
            method: "window.focus",
            params: {
                window_id: windowId,
                project_name: stringOrEmpty(windowData.project),
                target_variant: stringOrEmpty(windowData.execution_mode),
                connection_key: stringOrEmpty(windowData.connection_key),
            },
        };
    }

    function windowFastFocusEligible(windowData) {
        const mode = stringOrEmpty(windowData && windowData.execution_mode).toLowerCase();
        const connectionKey = stringOrEmpty(windowData && windowData.connection_key);
        if (mode === "ssh") {
            const hostName = hostNameFromConnectionKey(connectionKey);
            return normalizeHostAlias(hostName) === currentHostAlias();
        }
        return true;
    }

    function focusWindow(windowData) {
        const target = windowFocusTarget(windowData);
        if (!target) {
            return;
        }

        runFocusTarget(target);
    }

    function sessionClosableWindowId(session) {
        const windowId = Number(session && session.window_id || 0);
        if (windowId > 0) {
            return windowId;
        }

        return 0;
    }

    function sessionCloseKey(session) {
        return stringOrEmpty(session && (session.session_key || session.herdr_session || session.pane_id));
    }

    function sessionCloseTarget(session) {
        if (!session || typeof session !== "object") {
            return null;
        }
        return normalizedFocusTarget(session.close_target);
    }

    function markSessionClosePending(sessionKey) {
        const key = stringOrEmpty(sessionKey);
        if (!key) {
            return;
        }
        const next = Object.assign({}, sessionClosePendingMap);
        next[key] = Date.now();
        sessionClosePendingMap = next;
    }

    function sessionClosePending(session) {
        const key = sessionCloseKey(session);
        return key !== "" && Object.prototype.hasOwnProperty.call(sessionClosePendingMap, key);
    }

    function pruneSessionClosePending() {
        const next = {};
        const now = Date.now();
        const liveKeys = {};
        const sessions = activeSessions();
        for (let i = 0; i < sessions.length; i += 1) {
            const sessionKey = sessionCloseKey(sessions[i]);
            if (sessionKey) {
                liveKeys[sessionKey] = true;
            }
        }
        for (const key in sessionClosePendingMap) {
            if (!Object.prototype.hasOwnProperty.call(sessionClosePendingMap, key)) {
                continue;
            }
            const startedAt = Number(sessionClosePendingMap[key] || 0);
            if (liveKeys[key] && now - startedAt < 15000) {
                next[key] = startedAt;
            }
        }
        sessionClosePendingMap = next;
    }

    function sessionHasClosableSurface(session) {
        if (sessionCloseTarget(session)) {
            return true;
        }
        return sessionClosableWindowId(session) > 0;
    }

    function closeSession(session) {
        if (!session) {
            return;
        }

        const sessionKey = sessionCloseKey(session);
        if (sessionClosePending(session)) {
            return;
        }

        const explicitCloseTarget = sessionCloseTarget(session);
        if (explicitCloseTarget) {
            markSessionClosePending(sessionKey);
            runDaemonCall(explicitCloseTarget.method, explicitCloseTarget.params);
            return;
        }

        const windowId = sessionClosableWindowId(session);
        if (!windowId) {
            return;
        }
        if (sessionKey) {
            markSessionClosePending(sessionKey);
        }

        closeWindow({
            id: windowId,
            window_id: windowId,
            project: stringOrEmpty(session.project_name || session.project),
            execution_mode: stringOrEmpty(session.execution_mode || session.focus_execution_mode),
            connection_key: stringOrEmpty(session.connection_key || session.focus_connection_key),
        });
    }

    function activateWorkspace(workspace) {
        if (!workspace) {
            return;
        }

        const workspaceName = workspaceNameValue(workspace);
        if (!workspaceName) {
            return;
        }

        beginLocalFocusIntent("workspace.focus_fast", {workspace: workspaceName});
        if (!runDaemonSocketCall("workspace.focus_fast", {workspace: workspaceName})) {
            localFocusIntent = null;
        }
    }

    function closeWindow(windowData) {
        if (!windowData) {
            return;
        }

        const windowId = Number(windowData.id || windowData.window_id || 0);
        if (!windowId) {
            return;
        }

        const project = stringOrEmpty(windowData.project);
        const variant = stringOrEmpty(windowData.execution_mode);
        const params = {
            window_id: windowId,
            action: "kill",
            project_name: project,
            target_variant: variant,
            connection_key: stringOrEmpty(windowData.connection_key),
        };

        if (runDaemonSocketCall("window.action", params)) {
            return;
        }

        const command = [shellConfig.i3pmBin, "window", "action", String(windowId), "close"];
        if (project && project !== "global") {
            command.push("--project", project);
        }
        if (variant) {
            command.push("--variant", variant);
        }
        runDetached(command);
    }

    function clearContext() {
        root.worktreePickerVisible = false;
        runDetached([shellConfig.i3pmBin, "context", "clear"]);
    }

    function switchContext(projectName, targetHost) {
        const name = stringOrEmpty(projectName);
        const host = normalizeHostAlias(targetHost || currentHostAlias());
        if (!name || name === "global") {
            clearContext();
            return;
        }

        root.worktreePickerVisible = false;
        const command = [shellConfig.i3pmBin, "context", "ensure", name];
        if (host) {
            command.push("--host", host);
        }
        runDetached(command);
    }

    function activateWorktree(item, targetHost) {
        if (!item) {
            return;
        }

        const kind = stringOrEmpty(item.kind);
        if (kind === "global") {
            if (!isGlobalContext()) {
                clearContext();
            }
            return;
        }

        const projectName = stringOrEmpty(item.qualified_name);
        const requestedHost = normalizeHostAlias(targetHost || currentHostAlias());
        const activeProject = activeContextProjectName();
        const activeHost = activeContextTargetHost();

        if (projectName === activeProject && requestedHost === activeHost) {
            focusPreferredWindowForContext(projectName, requestedHost);
            return;
        }

        switchContext(projectName, requestedHost);
    }

    function cycleDisplayLayout() {
        runDetached([shellConfig.i3pmBin, "display", "cycle"]);
    }

    function triggerPowerAction(command) {
        root.powerMenuVisible = false;
        runDetached(command);
    }

    function emptyDashboardState(status, errorMessage) {
        return {
            status: stringOrEmpty(status) || "loading",
            error: stringOrEmpty(errorMessage),
            active_context: {},
            active_terminal: {},
            active_ai_sessions: [],
            display_layout: {},
            outputs: [],
            projects: [],
            worktrees: [],
            herdr: {
                spaces: [],
            },
            scratchpad: {},
            state_health: {},
            total_windows: 0
        };
    }

    function dashboardHasUsableData(state) {
        if (!state || typeof state !== "object") {
            return false;
        }

        return arrayOrEmpty(state.active_ai_sessions).length > 0
            || arrayOrEmpty(state.projects).length > 0
            || arrayOrEmpty(state.outputs).length > 0
            || arrayOrEmpty(state.worktrees).length > 0
            || Number(state.total_windows || 0) > 0;
    }

    function dashboardStateWithStatus(baseState, status, errorMessage) {
        const base = (baseState && typeof baseState === "object")
            ? baseState
            : root.emptyDashboardState(status, errorMessage);
        return Object.assign({}, base, {
            status: stringOrEmpty(status) || "loading",
            error: stringOrEmpty(errorMessage),
        });
    }

    function resetDashboard(status, errorMessage) {
        dashboard = root.dashboardHasUsableData(dashboard)
            ? root.dashboardStateWithStatus(dashboard, status, errorMessage)
            : root.emptyDashboardState(status, errorMessage);
        if (launcherVisible && (launcherMode === "sessions" || launcherMode === "windows")) {
            restartLauncherQuery();
        }
    }

    function dashboardGeneration(state) {
        return DashboardState.dashboardGeneration(state);
    }

    function dashboardFocusInvariantIssues(state) {
        return DashboardState.focusInvariantIssues(root, state);
    }

    function checkDashboardFocusInvariants(state) {
        const issues = dashboardFocusInvariantIssues(state);
        const message = issues.join(",");
        if (!message || message === lastDashboardInvariantWarning) {
            return;
        }
        lastDashboardInvariantWarning = message;
        console.warn("dashboard.invariant:", message);
    }

    function afterDashboardApplied() {
        checkDashboardFocusInvariants(dashboard);
        syncDisplayApplyStateFromDashboard();
        pruneSessionClosePending();
        clearLocalFocusIntentIfSettled();
        if (launcherVisible && (launcherMode === "sessions" || launcherMode === "windows")) {
            restartLauncherQuery();
        }
    }

    function applySnapshot(snapshot) {
        if (!snapshot || typeof snapshot !== "object") {
            return;
        }
        dashboard = snapshot;
        afterDashboardApplied();
    }

    function dashboardEventPayload(event) {
        if (!event || typeof event !== "object") {
            return null;
        }
        const payload = event.payload || {};
        return payload && typeof payload === "object" && !Array.isArray(payload) ? payload : null;
    }

    function dashboardEventChangedKeys(event) {
        if (!event || typeof event !== "object") {
            return [];
        }
        return arrayOrEmpty(event.changed_keys).map(key => stringOrEmpty(key)).filter(key => key.length > 0);
    }

    function applyEvent(event) {
        if (!event || typeof event !== "object") {
            return;
        }

        const eventType = stringOrEmpty(event.event_type || event.type);
        const changedKeys = dashboardEventChangedKeys(event);
        const eventGeneration = dashboardGeneration(event);
        const currentGeneration = dashboardGeneration(dashboard);
        if (eventGeneration >= 0 && currentGeneration >= 0 && eventGeneration <= currentGeneration) {
            return;
        }

        const payload = dashboardEventPayload(event);
        if (
            eventType === "dashboard.invalidated"
            || changedKeys.indexOf("dashboard") !== -1
            || !payload
        ) {
            resetDashboard("reconnecting", eventType || "dashboard invalidated");
            return;
        }

        if (eventGeneration >= 0 && currentGeneration >= 0 && eventGeneration > currentGeneration + 1) {
            resetDashboard("reconnecting", "dashboard event generation gap");
            return;
        }

        dashboard = Object.assign({}, dashboard, payload, {
            snapshot_version: eventGeneration >= 0 ? eventGeneration : (payload.snapshot_version || dashboard.snapshot_version || 0),
            session_generation: event.session_generation !== undefined ? event.session_generation : (payload.session_generation || dashboard.session_generation || 0),
            display_generation: event.display_generation !== undefined ? event.display_generation : (payload.display_generation || dashboard.display_generation || 0),
            focus_generation: event.focus_generation !== undefined ? event.focus_generation : (payload.focus_generation || dashboard.focus_generation || 0),
        });
        afterDashboardApplied();
    }

    function handleDashboardWatchError(payload) {
        const message = stringOrEmpty(payload).trim();
        if (!message) {
            return;
        }
        console.warn("dashboard.watch:", message);
        if (message.indexOf("Bad resource ID") !== -1 || message.indexOf("Fatal error") !== -1) {
            root.resetDashboard("reconnecting", message);
            dashboardWatcher.running = false;
            dashboardRestartTimer.restart();
        }
    }

    function handleDaemonActionResponse(payload) {
        const raw = stringOrEmpty(payload).trim();
        if (!raw || raw === "undefined" || raw === "null") {
            return;
        }
        try {
            const response = JSON.parse(raw);
            if (response && response.error) {
                console.warn("daemon.action:", stringOrEmpty(response.error.message || response.error));
                localFocusIntent = null;
                return;
            }
            const result = response && typeof response.result === "object" ? response.result : null;
            const focusIntent = result && typeof result.focus_intent === "object" ? result.focus_intent : null;
            if (focusIntent) {
                const intentState = stringOrEmpty(focusIntent.state);
                if (localFocusIntentMatches(focusIntent) && intentState === "failed") {
                    localFocusIntent = null;
                }
                const currentFocus = dashboard && typeof dashboard.focus_state === "object" ? dashboard.focus_state : {};
                dashboard = Object.assign({}, dashboard, {
                    focus_state: Object.assign({}, currentFocus, {
                        pending_intent_id: intentState === "pending" ? stringOrEmpty(focusIntent.intent_id) : "",
                        focus_intent: focusIntent,
                    }),
                });
                clearLocalFocusIntentIfSettled();
            }
        } catch (error) {
            console.warn("daemon.action: invalid response", error);
        }
    }

    function parseDashboard(payload) {
        const raw = stringOrEmpty(payload).trim();
        if (!raw || raw === "undefined" || raw === "null") {
            return;
        }
        if (!(raw.indexOf("{") === 0 || raw.indexOf("[") === 0)) {
            return;
        }

        try {
            const parsed = JSON.parse(raw);
            if (parsed && typeof parsed === "object" && !Array.isArray(parsed) && parsed.event_type !== undefined) {
                applyEvent(parsed);
            } else {
                applySnapshot(parsed);
            }
        } catch (error) {
            console.warn("Failed to parse dashboard payload", error, raw);
        }
    }

    function parseNotification(payload) {
        const raw = stringOrEmpty(payload).trim();
        if (!raw || raw === "undefined" || raw === "null") {
            return;
        }
        if (raw.indexOf("{") !== 0) {
            return;
        }

        try {
            notificationState = JSON.parse(raw);
        } catch (error) {
            console.warn("Failed to parse notification payload", error, raw);
        }
    }

    function parseNetwork(payload) {
        const raw = stringOrEmpty(payload).trim();
        if (!raw || raw === "undefined" || raw === "null") {
            return;
        }
        if (raw.indexOf("{") !== 0) {
            return;
        }

        try {
            networkState = JSON.parse(raw);
        } catch (error) {
            console.warn("Failed to parse network payload", error, raw);
        }
    }

    function parseVoxtype(payload) {
        const raw = stringOrEmpty(payload).trim();
        if (!raw || raw.indexOf("{") !== 0) {
            return;
        }
        try {
            const next = JSON.parse(raw);
            voxtypeState = next;
            const cls = stringOrEmpty((next && next.class) || "idle");
            if (voxtypeStopRequested && cls !== "recording" && cls !== "streaming") {
                clearVoxtypeStopRequest();
            }
        } catch (error) {
            console.warn("Failed to parse voxtype payload", error, raw);
        }
    }

    function parseDictationLevel(payload) {
        const raw = stringOrEmpty(payload).trim();
        if (!raw) {
            return;
        }
        const v = parseInt(raw, 10);
        if (isNaN(v)) {
            return;
        }
        dictationLevel = Math.max(0, Math.min(100, v));
    }

    function resetDictationLevel() {
        dictationLevel = 0;
    }

    function voxtypeRawClass() {
        const c = stringOrEmpty((voxtypeState && voxtypeState.class) || "idle");
        if (c === "recording" || c === "streaming" || c === "transcribing") {
            return c;
        }
        return "idle";
    }

    function voxtypeRawListening() {
        const c = voxtypeRawClass();
        return c === "recording" || c === "streaming";
    }

    function voxtypeClass() {
        const c = voxtypeRawClass();
        if (voxtypeStopRequested && (c === "recording" || c === "streaming")) {
            return "stopping";
        }
        return c;
    }

    function voxtypeActive() {
        const c = voxtypeClass();
        return c === "recording" || c === "streaming" || c === "transcribing" || c === "stopping";
    }

    function voxtypeListening() {
        const c = voxtypeClass();
        return c === "recording" || c === "streaming";
    }

    // FiraCode Nerd Font glyphs: mic/listen, broadcast tower (streaming),
    // hourglass (transcribing).
    function voxtypeIcon() {
        const c = voxtypeClass();
        if (c === "transcribing" || c === "stopping") {
            return "";
        }
        if (c === "streaming") {
            return "";
        }
        return "";
    }

    function voxtypeIconColor() {
        const c = voxtypeClass();
        if (c === "recording" || c === "streaming") {
            return colors.red;
        }
        if (c === "transcribing" || c === "stopping") {
            return colors.amber;
        }
        return colors.muted;
    }

    function voxtypeLabel() {
        const c = voxtypeClass();
        if (c === "recording") {
            return "REC";
        }
        if (c === "streaming") {
            return "LIVE";
        }
        if (c === "stopping") {
            return "STOP";
        }
        if (c === "transcribing") {
            return "…";
        }
        return "";
    }

    function markVoxtypeStopRequested() {
        voxtypeStopRequested = true;
        voxtypeStopIntentTimer.restart();
    }

    function clearVoxtypeStopRequest() {
        voxtypeStopRequested = false;
        voxtypeStopIntentTimer.stop();
    }

    function runDictationAction(action) {
        const requested = stringOrEmpty(action || "toggle") || "toggle";
        let commandAction = requested;
        const listening = voxtypeRawListening();

        if (requested === "toggle" && listening) {
            commandAction = "stop";
        }

        if ((commandAction === "stop" || commandAction === "cancel") && listening) {
            if (voxtypeStopRequested) {
                return;
            }
            markVoxtypeStopRequested();
        } else if (commandAction === "start" || requested === "toggle") {
            clearVoxtypeStopRequest();
        }

        runDetached([shellConfig.dictationBin, commandAction]);
    }

    function parseBrightness(payload) {
        const raw = stringOrEmpty(payload).trim();
        if (!raw || raw === "undefined" || raw === "null") {
            return;
        }
        if (raw.indexOf("{") !== 0) {
            return;
        }

        try {
            const next = JSON.parse(raw);
            brightnessState = Object.assign({}, brightnessState, next);
        } catch (error) {
            console.warn("Failed to parse brightness payload", error, raw);
        }
    }

    function parseLidPolicy(payload) {
        const raw = stringOrEmpty(payload).trim();
        if (!raw || raw === "undefined" || raw === "null") {
            return;
        }
        if (raw.indexOf("{") !== 0) {
            return;
        }

        try {
            const next = JSON.parse(raw);
            lidPolicyState = Object.assign({}, lidPolicyState, next);
            syncLidPolicyDraft(false);
        } catch (error) {
            console.warn("Failed to parse lid policy payload", error, raw);
        }
    }

    function parseDaemonHealth(payload) {
        const raw = stringOrEmpty(payload).trim();
        if (!raw || raw.indexOf("{") !== 0) {
            return;
        }
        try {
            daemonHealthState = Object.assign({}, daemonHealthState, JSON.parse(raw));
        } catch (error) {
            console.warn("Failed to parse daemon health payload", error, raw);
        }
    }

    function daemonHealthLabel() {
        const status = stringOrEmpty(daemonHealthState.status);
        if (status === "healthy") return "Daemon";
        if (status === "degraded") return "Daemon !";
        if (status === "unhealthy" || status === "critical") return "Daemon !!";
        if (status === "dead" || status === "unreachable") return "Daemon X";
        return "Daemon ?";
    }

    function daemonHealthColor(hovered) {
        const status = stringOrEmpty(daemonHealthState.status);
        if (status === "healthy") return neutralChipFill(hovered);
        if (status === "degraded") return hovered ? Qt.lighter(colors.amberBg, 1.15) : colors.amberBg;
        return hovered ? Qt.lighter(colors.redBg, 1.15) : colors.redBg;
    }

    function daemonHealthBorderColor(hovered) {
        const status = stringOrEmpty(daemonHealthState.status);
        if (status === "healthy") return neutralChipBorder(hovered);
        if (status === "degraded") return colors.amber;
        return colors.red;
    }

    function daemonHealthTextColor(hovered) {
        const status = stringOrEmpty(daemonHealthState.status);
        if (status === "healthy") return neutralChipText(hovered);
        if (status === "degraded") return hovered ? colors.amber : colors.subtle;
        return hovered ? colors.red : colors.subtle;
    }

    function daemonHealthDotColor() {
        const status = stringOrEmpty(daemonHealthState.status);
        if (status === "healthy") return colors.green || colors.accent;
        if (status === "degraded") return colors.amber;
        if (status === "dead" || status === "unreachable") return colors.red;
        return colors.muted;
    }

    function daemonHealthTooltip() {
        const s = daemonHealthState;
        const uptime = Math.round(Number(s.uptime || 0));
        const uptimeLabel = uptime >= 3600
            ? Math.floor(uptime / 3600) + "h " + Math.floor((uptime % 3600) / 60) + "m"
            : uptime >= 60 ? Math.floor(uptime / 60) + "m " + (uptime % 60) + "s"
            : uptime + "s";
        const bits = [
            "Status: " + stringOrEmpty(s.status),
            "Uptime: " + uptimeLabel,
            "Events: " + String(s.events || 0),
            "Windows: " + String(s.windows || 0)
        ];
        if (s.issues) {
            bits.push("Issues: " + String(s.issues));
        }
        return bits.join("\n");
    }

    function moonlightChipLabel() {
        const status = moonlightStatus();
        if (!boolOrFalse(status && status.present)) {
            return "";
        }
        if (boolOrFalse(status.captureInferred)) {
            return "Moonlight Captured";
        }
        if (boolOrFalse(status.fullscreen)) {
            return "Moonlight FS";
        }
        return "Moonlight";
    }

    function moonlightChipFill(hovered) {
        const status = moonlightStatus();
        if (boolOrFalse(status.captureInferred)) {
            return hovered ? Qt.lighter(colors.blueBg, 1.12) : colors.blueBg;
        }
        if (boolOrFalse(status.focused)) {
            return hovered ? Qt.lighter(colors.blueWash, 1.08) : colors.blueWash;
        }
        return neutralChipFill(hovered);
    }

    function moonlightChipBorder(hovered) {
        const status = moonlightStatus();
        if (boolOrFalse(status.captureInferred)) {
            return colors.blue;
        }
        if (boolOrFalse(status.focused)) {
            return colors.blueMuted;
        }
        return neutralChipBorder(hovered);
    }

    function moonlightChipText(hovered) {
        const status = moonlightStatus();
        if (boolOrFalse(status.captureInferred)) {
            return colors.blue;
        }
        if (boolOrFalse(status.focused)) {
            return colors.text;
        }
        return neutralChipText(hovered);
    }

    function moonlightChipTooltip() {
        const status = moonlightStatus();
        const bits = [
            "Running: " + (boolOrFalse(status && status.present) ? "yes" : "no")
        ];
        if (!boolOrFalse(status && status.present)) {
            return bits.join("\n");
        }

        bits.push("Focused: " + (boolOrFalse(status.focused) ? "yes" : "no"));
        bits.push("Fullscreen: " + (boolOrFalse(status.fullscreen) ? "yes" : "no"));
        if (stringOrEmpty(status.workspace)) {
            bits.push("Workspace: " + status.workspace);
        }
        if (stringOrEmpty(status.output)) {
            bits.push("Output: " + status.output);
        }
        if (stringOrEmpty(status.title)) {
            bits.push("Title: " + status.title);
        }
        if (Number(status.windowCount || 0) > 1) {
            bits.push("Windows: " + String(Number(status.windowCount || 0)));
        }
        bits.push("Capture: inferred from Moonlight focus + fullscreen on Sway");
        bits.push("Exact shortcut/input capture is not exposed as a stable external signal.");
        return bits.join("\n");
    }

    function parseSystemStats(payload) {
        const raw = stringOrEmpty(payload).trim();
        if (!raw || raw === "undefined" || raw === "null") {
            return;
        }
        if (raw.indexOf("{") !== 0) {
            return;
        }

        try {
            systemStatsState = Object.assign({}, systemStatsState, JSON.parse(raw));
        } catch (error) {
            console.warn("Failed to parse system stats payload", error, raw);
        }
    }

    Controllers.RuntimeServices {
        id: runtimeServices
        shellRoot: shellRootRef
        runtimeConfig: shellConfig
    }


    // Click-away scrim for the top-bar display selector popup. Declared BEFORE
    // the bars so its layer surface is created first and therefore sits BELOW the
    // bars and the bar's popup (the card stays clickable, on top). It is always
    // mapped but only captures input while the popup is open — otherwise its mask
    // is empty, so it renders nothing and clicks pass straight through to the
    // windows underneath. Clicking anywhere outside the card closes the popup.
    Variants {
        model: shellRootRef.useFallbackScreenWindows ? [] : Quickshell.screens
        delegate: PanelWindow {
            required property var modelData
            screen: modelData
            visible: true
            color: "transparent"
            exclusiveZone: 0
            WlrLayershell.namespace: "i3pm-display-scrim"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true
            mask: shellRootRef.displaySelectorVisible ? scrimFullRegion : scrimEmptyRegion

            Region {
                id: scrimEmptyRegion
            }
            Region {
                id: scrimFullRegion
                item: scrimCatcher
            }

            MouseArea {
                id: scrimCatcher
                anchors.fill: parent
                enabled: shellRootRef.displaySelectorVisible
                onClicked: shellRootRef.closeDisplaySelector()
            }
        }
    }

    Variants {
        model: shellRootRef.useFallbackScreenWindows ? [] : Quickshell.screens
        delegate: Windows.TopBarWindow {
            shellRoot: shellRootRef
            runtimeConfig: shellConfig
            colors: shellRootRef.colors
        }
    }

    // Click-away backdrop for the top-bar chip popups (volume / bluetooth / power
    // / displays). QuickShell's PopupWindow has no built-in dismiss-on-click-
    // outside, so this transparent layer covers the screen BELOW the bar whenever a
    // popup is open on that monitor; a press anywhere on it closes the popup. It is
    // pointer-only (focusable:false, keyboardFocus None) so it never grabs the
    // keyboard or steals focus, and it leaves the top bar strip uncovered so the
    // chips stay clickable (re-click to toggle, click another chip to switch).
    Variants {
        model: shellRootRef.useFallbackScreenWindows ? [] : Quickshell.screens
        delegate: PanelWindow {
            required property var modelData
            readonly property string backdropOutputName: shellRootRef.screenOutputName(modelData)
            screen: modelData
            visible: shellRootRef.anyBarPopupOpenOnOutput(backdropOutputName)
            color: "transparent"
            anchors.left: true
            anchors.right: true
            anchors.bottom: true
            implicitHeight: Math.max(0, (modelData ? modelData.height : 1080) - shellConfig.barHeight)
            exclusiveZone: 0
            focusable: false
            aboveWindows: true
            WlrLayershell.namespace: "i3pm-bar-popup-backdrop"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onPressed: shellRootRef.closeBarPopups()
            }
        }
    }

    Windows.TopBarWindow {
        visible: shellRootRef.useFallbackScreenWindows && shellConfig.perMonitorBars
        modelData: null
        fallbackMode: true
        fallbackOutputName: shellRootRef.fallbackOutputName
        shellRoot: shellRootRef
        runtimeConfig: shellConfig
        colors: shellRootRef.colors
    }

    Variants {
        model: shellRootRef.useFallbackScreenWindows ? [] : Quickshell.screens
        delegate: Windows.BottomBarWindow {
            shellRoot: shellRootRef
            runtimeConfig: shellConfig
            colors: shellRootRef.colors
        }
    }

    Windows.BottomBarWindow {
        modelData: null
        fallbackMode: true
        fallbackOutputName: shellRootRef.fallbackOutputName
        visible: shellRootRef.useFallbackScreenWindows && shellConfig.perMonitorBars
        shellRoot: shellRootRef
        runtimeConfig: shellConfig
        colors: shellRootRef.colors
    }

    Variants {
        model: shellRootRef.useFallbackScreenWindows ? [] : Quickshell.screens
        delegate: Windows.ToastWindow {
            shellRoot: shellRootRef
            runtimeConfig: shellConfig
            colors: shellRootRef.colors
        }
    }

    Windows.NotificationDetailWindow {
        shellRoot: shellRootRef
        runtimeConfig: shellConfig
        colors: shellRootRef.colors
    }

    Windows.AgentMonitorWindow {
        shellRoot: shellRootRef
        runtimeConfig: shellConfig
        colors: shellRootRef.colors
    }

    Windows.LauncherWindow {
        id: launcherWindow
        shellRoot: shellRootRef
        runtimeConfig: shellConfig
        colors: shellRootRef.colors
    }

    Windows.SettingsWindow {
        id: settingsWindow
        shellRoot: shellRootRef
        runtimeConfig: shellConfig
        colors: shellRootRef.colors
    }

    Windows.RuntimePanelWindow {
        shellRoot: shellRootRef
        runtimeConfig: shellConfig
        colors: shellRootRef.colors
    }

    Windows.WindowSwitcherWindow {
        id: windowSwitcherWindow
        shellRoot: shellRootRef
        runtimeConfig: shellConfig
        colors: shellRootRef.colors
    }

    Windows.DictationOverlay {
        shellRoot: shellRootRef
        runtimeConfig: shellConfig
        colors: shellRootRef.colors
    }

}
