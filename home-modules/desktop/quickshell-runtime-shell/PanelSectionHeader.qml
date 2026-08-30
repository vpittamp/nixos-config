import QtQuick

// Caption above a panel section: small, bold, letter-spaced, dim.
Text {
    property string label: ""
    text: label.toUpperCase()
    color: Theme.subtle
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fs(8)
    font.weight: Font.Bold
    font.letterSpacing: 1.2
}
