"""Sample configuration data for testing."""

# Sample window-rules.json configurations
SAMPLE_WINDOW_RULES = [
    {
        "pattern_rule": {
            "pattern": "glob:FFPWA-*",
            "scope": "global",
            "priority": 200,
            "description": "Firefox PWAs (all global)"
        },
        "workspace": 4
    },
    {
        "pattern_rule": {
            "pattern": "title:^Yazi:.*",
            "scope": "scoped",
            "priority": 300,
            "description": "Yazi file manager in terminal"
        },
        "workspace": 5
    },
    {
        "pattern_rule": {
            "pattern": "Code",
            "scope": "scoped",
            "priority": 250,
            "description": "VS Code editor"
        },
        "workspace": 2
    },
    {
        "pattern_rule": {
            "pattern": "Ghostty",
            "scope": "scoped",
            "priority": 100,
            "description": "Default ghostty terminal"
        },
        "workspace": 1
    }
]

# Sample workspace-config.json configurations
SAMPLE_WORKSPACE_CONFIG = [
    {"number": 1, "name": "Terminal", "icon": "󰨊", "default_output_role": "primary"},
    {"number": 2, "name": "Editor", "icon": "", "default_output_role": "primary"},
    {"number": 3, "name": "Browser", "icon": "󰈹", "default_output_role": "secondary"},
    {"number": 4, "name": "Media", "icon": "", "default_output_role": "secondary"},
    {"number": 5, "name": "Files", "icon": "󰉋", "default_output_role": "secondary"},
    {"number": 6, "name": "Chat", "icon": "󰭹", "default_output_role": "tertiary"},
    {"number": 7, "name": "Email", "icon": "󰇮", "default_output_role": "tertiary"},
    {"number": 8, "name": "Music", "icon": "󰝚", "default_output_role": "tertiary"},
    {"number": 9, "name": "Misc", "icon": "󰇙", "default_output_role": "tertiary"}
]

# Sample app-classes.json with class_patterns (dict format - backward compatibility)
SAMPLE_APP_CLASSIFICATION_DICT = {
    "scoped_classes": ["Code", "Ghostty", "neovide"],
    "global_classes": ["firefox", "mpv", "obsidian"],
    "class_patterns": {
        "pwa-": "global",
        "terminal": "scoped"
    }
}

# Sample app-classes.json with class_patterns (list format - new)
SAMPLE_APP_CLASSIFICATION_LIST = {
    "scoped_classes": ["Code", "Ghostty"],
    "global_classes": ["firefox", "mpv"],
    "class_patterns": [
        {"pattern": "glob:pwa-*", "scope": "global", "priority": 100, "description": "Firefox PWAs"},
        {"pattern": "glob:*terminal*", "scope": "scoped", "priority": 90, "description": "Terminal apps"}
    ]
}

# Sample project configuration
SAMPLE_PROJECT = {
    "name": "nixos",
    "directory": "/etc/nixos",
    "display_name": "NixOS Config",
    "icon": "󱄅",
    "scoped_classes": ["Code", "Ghostty", "neovide"],
    "workspace_preferences": {
        "1": "primary",
        "2": "secondary",
        "5": "secondary"
    }
}

# PWA-specific test data
PWA_WINDOW_RULES = [
    {
        "pattern_rule": {
            "pattern": "glob:FFPWA-*",
            "scope": "global",
            "priority": 200,
            "description": "All Firefox PWAs"
        },
        "workspace": 4
    },
    {
        "pattern_rule": {
            "pattern": "pwa:YouTube",
            "scope": "global",
            "priority": 250,
            "description": "YouTube PWA with title matching"
        },
        "workspace": 4
    },
    {
        "pattern_rule": {
            "pattern": "pwa:Google AI Studio",
            "scope": "global",
            "priority": 250,
            "description": "Google AI Studio PWA"
        },
        "workspace": 3
    }
]

# Terminal app test data
TERMINAL_WINDOW_RULES = [
    {
        "pattern_rule": {
            "pattern": "title:^Yazi:.*",
            "scope": "scoped",
            "priority": 300,
            "description": "Yazi file manager"
        },
        "workspace": 5
    },
    {
        "pattern_rule": {
            "pattern": "title:^lazygit",
            "scope": "scoped",
            "priority": 300,
            "description": "Lazygit in terminal"
        },
        "workspace": 5
    },
    {
        "pattern_rule": {
            "pattern": "Ghostty",
            "scope": "scoped",
            "priority": 100,
            "description": "Plain ghostty terminal"
        },
        "workspace": 1
    }
]

# Multi-monitor test configurations
MONITOR_CONFIG_SINGLE = [
    {
        "name": "DP-1",
        "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080},
        "active": True,
        "primary": True,
        "role": "primary"
    }
]

MONITOR_CONFIG_DUAL = [
    {
        "name": "DP-1",
        "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080},
        "active": True,
        "primary": True,
        "role": "primary"
    },
    {
        "name": "DP-2",
        "rect": {"x": 1920, "y": 0, "width": 1920, "height": 1080},
        "active": True,
        "primary": False,
        "role": "secondary"
    }
]

MONITOR_CONFIG_TRIPLE = [
    {
        "name": "DP-1",
        "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080},
        "active": True,
        "primary": True,
        "role": "primary"
    },
    {
        "name": "DP-2",
        "rect": {"x": 1920, "y": 0, "width": 1920, "height": 1080},
        "active": True,
        "primary": False,
        "role": "secondary"
    },
    {
        "name": "HDMI-1",
        "rect": {"x": 3840, "y": 0, "width": 1920, "height": 1080},
        "active": True,
        "primary": False,
        "role": "tertiary"
    }
]

# Advanced rule modifier test data
ADVANCED_WINDOW_RULES = [
    {
        "pattern_rule": {
            "pattern": "glob:*",
            "scope": "global",
            "priority": 10,
            "description": "Global rule for all windows"
        },
        "modifier": "GLOBAL",
        "blacklist": ["URxvt", "Alacritty"],
        "command": "exec notify-send 'Window opened' '$CLASS'"
    },
    {
        "pattern_rule": {
            "pattern": "glob:*",
            "scope": "global",
            "priority": 1,
            "description": "Default fallback rule"
        },
        "modifier": "DEFAULT",
        "workspace": 9
    },
    {
        "pattern_rule": {
            "pattern": "Temporary",
            "scope": "global",
            "priority": 150,
            "description": "Temporary windows - notify on close"
        },
        "modifier": "ON_CLOSE",
        "command": "exec notify-send 'Window closed' '$CLASS: $TITLE'"
    }
]
