import QtQuick
import Quickshell
import "components"

Scope {
    id: root

    required property var notificationState

    Theme {
        id: toastTheme
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: toastWindow

            required property var modelData
            readonly property var groups: root.notificationState.popupGroupsForScreen(modelData.name)

            screen: modelData
            visible: groups.length > 0
            color: "transparent"
            implicitWidth: 350
            implicitHeight: toastColumn.implicitHeight
            aboveWindows: true
            focusable: false
            exclusiveZone: 0

            anchors {
                top: true
                right: true
            }

            margins {
                top: 88
                right: 20
            }

            Column {
                id: toastColumn

                width: 350
                spacing: 10

                Repeater {
                    model: toastWindow.groups

                    NotificationCard {
                        required property var modelData

                        theme: toastTheme
                        notificationState: root.notificationState
                        entry: modelData.latest
                        groupCount: modelData.entries.length
                        groupAppName: modelData.appName
                        toastMode: true
                    }
                }
            }
        }
    }
}
