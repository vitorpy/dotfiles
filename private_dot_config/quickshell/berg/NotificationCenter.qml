import QtQuick
import Quickshell
import "components"

PanelWindow {
    id: root

    required property var theme
    required property var notificationState

    readonly property string screenName: screen ? screen.name : ""

    visible: notificationState.centerOpen
        && notificationState.centerScreenName === screenName
    color: "transparent"
    implicitWidth: 420
    implicitHeight: Math.min(700, Math.max(320, screen ? screen.height - 104 : 700))
    aboveWindows: true
    focusable: false
    exclusiveZone: 0

    anchors {
        top: true
        right: true
    }

    margins {
        top: 69
        right: 16
    }

    Rectangle {
        anchors.fill: parent
        color: root.theme.surfaceContainerHigh
        border.color: root.theme.outlineVariant
        border.width: 1
        radius: 12

        Rectangle {
            id: header

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            height: 62
            color: "transparent"

            Text {
                anchors {
                    left: parent.left
                    leftMargin: 16
                    verticalCenter: parent.verticalCenter
                }
                text: `Notifications · ${root.notificationState.count}`
                color: root.theme.foreground
                font.family: root.theme.textFont
                font.pixelSize: 16
                font.weight: Font.DemiBold
            }

            Row {
                anchors {
                    right: parent.right
                    rightMargin: 12
                    verticalCenter: parent.verticalCenter
                }
                spacing: 8

                Rectangle {
                    width: dndLabel.implicitWidth + 20
                    height: 32
                    color: dndMouse.containsMouse
                        ? root.theme.hoverLayer
                        : (root.notificationState.dnd ? root.theme.error : root.theme.surfaceContainer)
                    border.color: root.notificationState.dnd ? root.theme.error : root.theme.outlineVariant
                    border.width: 1
                    radius: 8

                    Text {
                        id: dndLabel

                        anchors.centerIn: parent
                        text: root.notificationState.dnd ? "DND on" : "DND off"
                        color: root.notificationState.dnd ? root.theme.onErrorColor : root.theme.foreground
                        font.family: root.theme.textFont
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: dndMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.notificationState.toggleDnd()
                    }
                }

                Rectangle {
                    width: clearLabel.implicitWidth + 20
                    height: 32
                    color: clearMouse.containsMouse ? root.theme.hoverLayer : root.theme.surfaceContainer
                    border.color: root.theme.outlineVariant
                    border.width: 1
                    radius: 8
                    opacity: root.notificationState.count > 0 ? 1 : 0.5

                    Text {
                        id: clearLabel

                        anchors.centerIn: parent
                        text: "Clear all"
                        color: root.theme.foreground
                        font.family: root.theme.textFont
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: clearMouse

                        anchors.fill: parent
                        enabled: root.notificationState.count > 0
                        hoverEnabled: true
                        onClicked: root.notificationState.dismissAll()
                    }
                }

                Rectangle {
                    width: 32
                    height: 32
                    color: closeMouse.containsMouse ? root.theme.hoverLayer : root.theme.surfaceContainer
                    border.color: root.theme.outlineVariant
                    border.width: 1
                    radius: 8

                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: root.theme.foreground
                        font.family: root.theme.textFont
                        font.pixelSize: 18
                    }

                    MouseArea {
                        id: closeMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.notificationState.closeCenter()
                    }
                }
            }
        }

        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                top: header.bottom
            }
            height: 1
            color: root.theme.outlineVariant
        }

        Text {
            anchors.centerIn: notificationViewport
            visible: root.notificationState.count === 0
            text: "No notifications"
            color: root.theme.foregroundMuted
            font.family: root.theme.textFont
            font.pixelSize: 14
        }

        Flickable {
            id: notificationViewport

            anchors {
                left: parent.left
                right: parent.right
                top: header.bottom
                bottom: parent.bottom
                margins: 16
            }
            visible: root.notificationState.count > 0
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: groupsColumn.implicitHeight

            Column {
                id: groupsColumn

                width: notificationViewport.width
                spacing: 14

                Repeater {
                    model: root.notificationState.centerGroups

                    Column {
                        id: groupColumn

                        required property var modelData
                        width: groupsColumn.width
                        spacing: 8

                        Text {
                            width: parent.width
                            text: `${groupColumn.modelData.appName} · ${groupColumn.modelData.entries.length}`
                            color: root.theme.foregroundMuted
                            font.family: root.theme.textFont
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Repeater {
                            model: groupColumn.modelData.entries

                            NotificationCard {
                                required property var modelData

                                width: groupColumn.width
                                theme: root.theme
                                notificationState: root.notificationState
                                entry: modelData
                                toastMode: false
                            }
                        }
                    }
                }
            }
        }
    }
}
