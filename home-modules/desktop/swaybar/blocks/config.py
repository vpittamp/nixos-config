"""Configuration dataclasses for enhanced swaybar status generator."""

from dataclasses import dataclass


@dataclass
class VolumeColors:
    """Color theme for volume status block."""
    normal: str = "#a6e3a1"   # Green (Catppuccin Mocha)
    muted: str = "#6c7086"    # Gray


@dataclass
class BatteryColors:
    """Color theme for battery status block."""
    charging: str = "#a6e3a1"  # Green
    high: str = "#a6e3a1"      # Green (>50%)
    medium: str = "#f9e2af"    # Yellow (20-50%)
    low: str = "#f38ba8"       # Red (<20%)


@dataclass
class NetworkColors:
    """Color theme for network status block."""
    connected: str = "#a6e3a1"     # Green
    connecting: str = "#f9e2af"    # Yellow
    disconnected: str = "#6c7086"  # Gray
    disabled: str = "#6c7086"      # Gray
    weak: str = "#f9e2af"          # Yellow (<40% signal)


@dataclass
class BluetoothColors:
    """Color theme for bluetooth status block."""
    connected: str = "#89b4fa"   # Blue
    enabled: str = "#a6e3a1"     # Green
    disabled: str = "#6c7086"    # Gray


@dataclass
class ColorTheme:
    """Complete color theme for status bar.

    Default theme: Catppuccin Mocha
    """
    name: str
    volume: VolumeColors
    battery: BatteryColors
    network: NetworkColors
    bluetooth: BluetoothColors


@dataclass
class UpdateIntervals:
    """Update intervals for status blocks (in seconds)."""
    battery: int = 30      # Seconds
    volume: int = 1
    network: int = 5
    bluetooth: int = 10


@dataclass
class ClickHandlers:
    """Click handler commands for status blocks."""
    volume: str = "pavucontrol"
    network: str = "nm-connection-editor"
    bluetooth: str = "blueman-manager"
    battery: str = ""  # No default handler


@dataclass
class Config:
    """Complete status generator configuration.

    Loaded from NixOS home-manager configuration or defaults.
    """

    enabled: bool = True
    icon_font: str = "NerdFont"
    theme: ColorTheme = None  # Default theme loaded at init
    intervals: UpdateIntervals = None
    click_handlers: ClickHandlers = None

    # Hardware detection flags
    detect_battery: bool = True
    detect_bluetooth: bool = True

    def __post_init__(self):
        """Initialize default theme and intervals if not provided."""
        if self.theme is None:
            self.theme = ColorTheme(
                name="catppuccin-mocha",
                volume=VolumeColors(),
                battery=BatteryColors(),
                network=NetworkColors(),
                bluetooth=BluetoothColors()
            )
        if self.intervals is None:
            self.intervals = UpdateIntervals()
        if self.click_handlers is None:
            self.click_handlers = ClickHandlers()
