import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    required property var modelData
    required property var osdState

    readonly property string screenName: screen ? screen.name : ""

    function iconFor(key: string): string {
        switch (key) {
        case "volume-muted": return theme.speakerMuted;
        case "volume": return theme.speakerHigh;
        case "headphones": return theme.headphones;
        case "microphone-muted": return theme.microphoneMuted;
        case "microphone": return theme.microphone;
        case "brightness": return theme.brightness;
        case "power": return theme.power;
        case "media-next": return "⏭";
        case "media-previous": return "⏮";
        case "media-play": return "▶";
        case "media-pause": return "⏸";
        case "media-source": return "♫";
        case "media-play-pause": return "⏯";
        default: return theme.warning;
        }
    }

    function symbolIcon(key: string): bool {
        return key.indexOf("media-") !== 0;
    }

    screen: root.modelData
    visible: root.osdState.opened && root.osdState.screenName === root.screenName
    color: "transparent"
    aboveWindows: true
    focusable: false
    exclusiveZone: 0

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.namespace: "berg-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}

    Theme {
        id: theme
    }

    Rectangle {
        id: card

        width: Math.min(parent.width - 32, Math.max(260, contentRow.implicitWidth + 40))
        height: 84
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 64
        }
        color: theme.surfaceContainerHigh
        border.color: theme.outlineVariant
        border.width: 1
        radius: 14
        opacity: root.visible ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 100 }
        }

        Row {
            id: contentRow

            anchors.centerIn: parent
            spacing: 16

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.iconFor(root.osdState.iconKey)
                color: theme.foreground
                font.family: root.symbolIcon(root.osdState.iconKey)
                    ? theme.symbolFont
                    : theme.textFont
                font.pixelSize: 30
                font.weight: Font.DemiBold
            }

            Rectangle {
                visible: root.osdState.hasProgress
                width: 180
                height: 8
                anchors.verticalCenter: parent.verticalCenter
                color: theme.outlineVariant
                radius: 4

                Rectangle {
                    height: parent.height
                    width: parent.width * Math.max(0, Math.min(
                        1,
                        root.osdState.value / Math.max(1, root.osdState.maximum)
                    ))
                    color: theme.primary
                    radius: parent.radius

                    Behavior on width {
                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }
                }
            }

            Text {
                visible: root.osdState.message.length > 0
                width: Math.min(240, implicitWidth)
                anchors.verticalCenter: parent.verticalCenter
                text: root.osdState.message
                color: theme.foreground
                font.family: theme.textFont
                font.pixelSize: 18
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }
}
