"""Sample .desktop file fixtures for testing."""

from pathlib import Path
from typing import NamedTuple


class DesktopFile(NamedTuple):
    """Sample .desktop file for testing."""

    name: str
    content: str
    expected_class: str | None = None


SAMPLE_DESKTOP_FILES = [
    DesktopFile(
        name="firefox.desktop",
        content="""[Desktop Entry]
Name=Firefox Web Browser
Comment=Browse the World Wide Web
Exec=firefox %u
Icon=firefox
Terminal=false
Type=Application
Categories=Network;WebBrowser;
StartupWMClass=firefox
""",
        expected_class="firefox",
    ),
    DesktopFile(
        name="code.desktop",
        content="""[Desktop Entry]
Name=Visual Studio Code
Comment=Code Editing. Redefined.
Exec=code %F
Icon=vscode
Terminal=false
Type=Application
Categories=Development;IDE;
StartupWMClass=Code
""",
        expected_class="Code",
    ),
    DesktopFile(
        name="pwa-youtube.desktop",
        content="""[Desktop Entry]
Name=YouTube PWA
Comment=Watch videos on YouTube
Exec=firefox --name pwa-youtube https://youtube.com
Icon=youtube
Terminal=false
Type=Application
Categories=Network;AudioVideo;
""",
        expected_class="pwa-youtube",  # No StartupWMClass, requires detection
    ),
    DesktopFile(
        name="ghostty.desktop",
        content="""[Desktop Entry]
Name=Ghostty Terminal
Comment=Fast terminal emulator
Exec=ghostty
Icon=ghostty
Terminal=false
Type=Application
Categories=System;TerminalEmulator;
StartupWMClass=Ghostty
""",
        expected_class="Ghostty",
    ),
    DesktopFile(
        name="slack.desktop",
        content="""[Desktop Entry]
Name=Slack
Comment=Team collaboration tool
Exec=slack %U
Icon=slack
Terminal=false
Type=Application
Categories=Network;InstantMessaging;
""",
        expected_class="Slack",  # No StartupWMClass, may need detection
    ),
]


def create_test_desktop_file(tmp_path: Path, desktop_file: DesktopFile) -> Path:
    """Create a temporary .desktop file for testing.

    Args:
        tmp_path: pytest tmp_path fixture
        desktop_file: DesktopFile fixture

    Returns:
        Path to created .desktop file
    """
    file_path = tmp_path / desktop_file.name
    file_path.write_text(desktop_file.content)
    return file_path
