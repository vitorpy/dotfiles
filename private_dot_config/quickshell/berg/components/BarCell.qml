import QtQuick
import QtQuick.Controls

Item {
    id: root

    required property var theme
    default property alias content: contentRow.data
    property int minimumWidth: 0
    property int horizontalPadding: 10
    property int contentSpacing: 6
    property bool separator: false
    property bool interactive: false
    property string tooltipText: ""
    property color backgroundColor: "transparent"
    property color hoverColor: theme.hoverLayer
    property int cornerRadius: 0

    readonly property bool hovered: mouseArea.containsMouse

    signal leftClicked
    signal rightClicked
    signal middleClicked
    signal wheelUp
    signal wheelDown

    implicitWidth: Math.max(minimumWidth, contentRow.implicitWidth + horizontalPadding * 2)
    implicitHeight: 54
    width: implicitWidth
    height: implicitHeight

    Rectangle {
        anchors.fill: parent
        color: root.backgroundColor
        radius: root.cornerRadius
    }

    Rectangle {
        visible: root.separator
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: root.theme.outlineVariant
    }

    Rectangle {
        visible: root.interactive && root.hovered
        anchors.fill: parent
        color: root.hoverColor
        radius: 8
    }

    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: root.contentSpacing
    }

    MouseArea {
        id: mouseArea
        enabled: root.interactive || root.tooltipText.length > 0
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton)
                root.leftClicked();
            else if (mouse.button === Qt.RightButton)
                root.rightClicked();
            else if (mouse.button === Qt.MiddleButton)
                root.middleClicked();
        }

        onWheel: wheel => {
            if (wheel.angleDelta.y > 0)
                root.wheelUp();
            else if (wheel.angleDelta.y < 0)
                root.wheelDown();
        }
    }

    ToolTip {
        id: tooltip

        visible: root.tooltipText.length > 0 && mouseArea.containsMouse
        text: root.tooltipText
        delay: 500
        timeout: -1
        y: root.height + 8
        popupType: Popup.Window
        leftPadding: 14
        rightPadding: 14
        topPadding: 12
        bottomPadding: 12

        contentItem: Text {
            text: tooltip.text
            color: root.theme.foreground
            font.family: root.theme.textFont
            font.pixelSize: root.theme.tooltipFontSize
            font.weight: Font.Medium
        }

        background: Rectangle {
            color: root.theme.tooltipSurface
            border.color: root.theme.outlineVariant
            border.width: 1
            radius: 12
        }
    }
}
