import QtQuick
import QtQuick.Layouts

// Panel header in Omarchy's shape: a large glyph (or image), a bold title,
// a dim meta line, and room for one trailing control. Every bar panel opens
// with one of these so they read as a family.
RowLayout {
    id: hero
    property string glyph: ""
    property string iconSource: ""
    property string title: ""
    property string meta: ""
    property color glyphColor: Theme.text
    property color metaColor: Theme.subtle
    default property alias trailing: trailingRow.data

    Layout.fillWidth: true
    spacing: 12

    Text {
        visible: hero.glyph !== ""
        text: hero.glyph
        color: hero.glyphColor
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(22)
        Layout.alignment: Qt.AlignVCenter
    }

    Image {
        visible: hero.iconSource !== ""
        source: hero.iconSource
        sourceSize.width: Theme.fs(22)
        sourceSize.height: Theme.fs(22)
        width: Theme.fs(22)
        height: Theme.fs(22)
        smooth: true
        Layout.alignment: Qt.AlignVCenter
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 1

        Text {
            text: hero.title
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(13)
            font.weight: Font.Bold
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        Text {
            visible: hero.meta !== ""
            text: hero.meta
            color: hero.metaColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(9)
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
    }

    RowLayout {
        id: trailingRow
        spacing: 6
    }
}
