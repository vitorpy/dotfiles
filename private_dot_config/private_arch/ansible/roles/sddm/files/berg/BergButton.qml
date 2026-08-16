import QtQuick 2.15

Rectangle {
    id: root

    property alias text: label.text
    property bool danger: false
    property bool filled: false
    property color accent: danger ? "#d54135" : "#f49f31"

    signal clicked()

    implicitWidth: Math.max(108, label.implicitWidth + 32)
    implicitHeight: 42
    radius: 12
    color: {
        if (!enabled)
            return "#282828";

        if (filled)
            return mouse.containsMouse || activeFocus ? Qt.lighter(accent, 1.08) : accent;

        return mouse.containsMouse || activeFocus ? "#282828" : "#202020";
    }
    border.width: filled ? 0 : (activeFocus ? 2 : 1)
    border.color: activeFocus || mouse.containsMouse ? accent : "#646667"
    opacity: enabled ? 1 : 0.55
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.clicked();
            event.accepted = true;
        }
    }

    Text {
        id: label

        anchors.centerIn: parent
        color: root.filled ? "#000000" : "#d7d7d7"
        font.family: "Noto Sans"
        font.pixelSize: 14
        font.weight: Font.DemiBold
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

}
