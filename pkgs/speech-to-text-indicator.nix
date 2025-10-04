{ lib, pkgs, makeWrapper, python3 }:

pkgs.stdenv.mkDerivation {
  pname = "speech-to-text-indicator";
  version = "1.1";

  src = pkgs.writeTextFile {
    name = "speech-to-text-indicator.py";
    text = ''
      #!/usr/bin/env python3
      import sys
      import subprocess
      import time
      from PyQt6.QtWidgets import QApplication, QSystemTrayIcon, QMenu
      from PyQt6.QtGui import QIcon, QAction, QPixmap, QPainter, QColor
      from PyQt6.QtCore import QTimer, Qt

      class SpeechIndicator:
          def __init__(self):
              self.app = QApplication(sys.argv)
              self.app.setQuitOnLastWindowClosed(False)

              # Create system tray icon
              self.tray = QSystemTrayIcon()

              # Animation state for blinking
              self.blink_state = True
              self.blink_timer = QTimer()
              self.blink_timer.timeout.connect(self.toggle_blink)

              self.update_icon()

              # Create menu
              self.menu = QMenu()

              self.status_action = QAction("Status: Off")
              self.status_action.setEnabled(False)
              self.menu.addAction(self.status_action)

              self.menu.addSeparator()

              toggle_action = QAction("Toggle Dictation (Meta+Shift+Space)")
              toggle_action.triggered.connect(self.toggle_dictation)
              self.menu.addAction(toggle_action)

              self.menu.addSeparator()

              quit_action = QAction("Quit")
              quit_action.triggered.connect(self.app.quit)
              self.menu.addAction(quit_action)

              self.tray.setContextMenu(self.menu)
              self.tray.activated.connect(self.on_tray_clicked)
              self.tray.show()

              # Update status every second
              self.timer = QTimer()
              self.timer.timeout.connect(self.update_status)
              self.timer.start(1000)

              # Initial status check
              self.update_status()

          def is_active(self):
              try:
                  result = subprocess.run(
                      ['pgrep', '-fc', r'\.nerd-dictation-wrapped begin'],
                      capture_output=True,
                      text=True
                  )
                  count = int(result.stdout.strip() or '0')
                  return count > 0
              except:
                  return False

          def create_red_icon(self, blink_on=True):
              """Create a red microphone icon"""
              # Get the base microphone icon
              base_icon = QIcon.fromTheme("audio-input-microphone")
              pixmap = base_icon.pixmap(64, 64)

              # Create a red overlay
              if blink_on:
                  painter = QPainter(pixmap)
                  painter.setCompositionMode(QPainter.CompositionMode.CompositionMode_SourceAtop)
                  painter.fillRect(pixmap.rect(), QColor(255, 0, 0, 180))  # Red with transparency
                  painter.end()

              return QIcon(pixmap)

          def toggle_blink(self):
              """Toggle blink state for animation"""
              self.blink_state = not self.blink_state
              self.update_icon()

          def update_icon(self):
              active = self.is_active()
              if active:
                  # Red blinking microphone icon when active
                  self.tray.setIcon(self.create_red_icon(self.blink_state))
                  self.tray.setToolTip("Speech-to-Text: 🔴 RECORDING")
                  # Start blinking if not already started
                  if not self.blink_timer.isActive():
                      self.blink_timer.start(500)  # Blink every 500ms
              else:
                  # Stop blinking and show muted icon
                  self.blink_timer.stop()
                  self.tray.setIcon(QIcon.fromTheme("microphone-sensitivity-muted"))
                  self.tray.setToolTip("Speech-to-Text: Off")

          def update_status(self):
              active = self.is_active()
              status = "RECORDING" if active else "Off"
              self.status_action.setText(f"Status: {status}")
              self.update_icon()

          def toggle_dictation(self):
              subprocess.Popen(['/run/current-system/sw/bin/nerd-dictation-toggle'])
              # Wait a moment for process to start/stop, then update
              QTimer.singleShot(500, self.update_status)

          def on_tray_clicked(self, reason):
              if reason == QSystemTrayIcon.ActivationReason.Trigger:
                  self.toggle_dictation()

          def run(self):
              sys.exit(self.app.exec())

      if __name__ == '__main__':
          indicator = SpeechIndicator()
          indicator.run()
    '';
    executable = true;
  };

  nativeBuildInputs = [ makeWrapper ];

  buildInputs = [
    (python3.withPackages (ps: with ps; [ pyqt6 ]))
  ];

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/bin
    cp $src $out/bin/speech-to-text-indicator
    chmod +x $out/bin/speech-to-text-indicator

    wrapProgram $out/bin/speech-to-text-indicator \
      --prefix PATH : ${lib.makeBinPath [ pkgs.procps ]}
  '';

  meta = {
    description = "System tray indicator for speech-to-text dictation status";
    license = lib.licenses.mit;
  };
}
