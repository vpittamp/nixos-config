import QtQuick
import QtQuick.Layouts

Rectangle {
    id: sectionHeader

    required property var rootObject
    required property var colorsObject
    property string title: ""
    property string summary: ""
    property int count: 0
    property bool expanded: false
    property bool clickable: true
    // Section headers are chrome, not content: they stay neutral so the only
    // colour in the panel is status. Expanding is signalled by the surface
    // lifting one step and by the chevron picking up the accent — previously
    // the whole bar filled with the accent wash, which on an accented host read
    // as a saturated block competing with the agent rows underneath it.
    property color expandedFill: colorsObject.card
    property color collapsedFill: colorsObject.cardAlt
    property color expandedBorder: colorsObject.border
    property color collapsedBorder: colorsObject.border
    property color expandedAccent: colorsObject.blue
    property color collapsedAccent: colorsObject.muted

    signal clicked()

    Layout.fillWidth: true
    implicitHeight: 34
    radius: rootObject.radiusControl
    color: expanded ? expandedFill : collapsedFill
    border.color: expanded ? expandedBorder : collapsedBorder
    border.width: 1
    scale: sectionHeaderMouse.pressed && clickable ? 0.96 : 1.0

    Behavior on scale {
        NumberAnimation {
            duration: 90
            easing.type: Easing.OutQuad
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 8

        Text {
            text: sectionHeader.expanded ? "▾" : "▸"
            color: sectionHeader.expanded ? sectionHeader.expandedAccent : sectionHeader.collapsedAccent
            font.pixelSize: sectionHeader.rootObject.fontBody
            font.weight: Font.DemiBold
        }

        Text {
            text: sectionHeader.title
            color: sectionHeader.colorsObject.text
            font.pixelSize: sectionHeader.rootObject.fontTitle
            font.weight: Font.DemiBold
        }

        Text {
            Layout.fillWidth: true
            text: sectionHeader.summary
            color: sectionHeader.colorsObject.subtle
            font.pixelSize: sectionHeader.rootObject.fontCaption
            font.weight: Font.Medium
            elide: Text.ElideRight
        }

        // Count reads as a secondary badge: outlined rather than filled, so it
        // sits on either header surface without becoming a dark hole.
        Rectangle {
            width: sectionCount.implicitWidth + 12
            height: 20
            radius: sectionHeader.rootObject.radiusBadge
            color: sectionHeader.colorsObject.bg
            border.color: sectionHeader.colorsObject.border
            border.width: 1

            Text {
                id: sectionCount
                anchors.centerIn: parent
                text: String(sectionHeader.count)
                color: sectionHeader.colorsObject.muted
                font.pixelSize: sectionHeader.rootObject.fontCaption
                font.weight: Font.DemiBold
            }
        }
    }

    MouseArea {
        id: sectionHeaderMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: sectionHeader.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        enabled: sectionHeader.clickable
        onClicked: sectionHeader.clicked()
    }
}
