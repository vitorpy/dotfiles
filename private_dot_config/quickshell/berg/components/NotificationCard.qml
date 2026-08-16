import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Widgets

Rectangle {
    id: root

    required property var theme
    required property var notificationState
    required property var entry
    property bool toastMode: true
    property int groupCount: 1
    property string groupAppName: ""

    readonly property var notification: entry ? entry.notification : null
    readonly property var explicitActions: notification
        ? notification.actions.filter(action => action.identifier !== "default")
        : []
    readonly property bool critical: notification && notification.urgency === NotificationUrgency.Critical
    readonly property real progressValue: {
        if (!notification || !notification.hints)
            return -1;
        const value = Number(notification.hints["value"]);
        return Number.isFinite(value) && value >= 0 && value <= 100 ? value : -1;
    }
    readonly property string iconSource: resolveIcon()

    width: toastMode ? 350 : 388
    implicitHeight: Math.min(toastMode ? 150 : 1000, contentRow.implicitHeight + 30)
    height: implicitHeight
    color: theme.surfaceContainerHigh
    border.color: critical ? theme.error : theme.outlineVariant
    border.width: 2
    radius: 10
    clip: true

    function resolveIcon(): string {
        if (!notification)
            return "";
        if (notification.image)
            return notification.image;
        const icon = notification.appIcon || "";
        if (!icon)
            return "";
        if (/^(file|image|qrc|data):/.test(icon))
            return icon;
        if (icon.startsWith("/"))
            return `file://${icon}`;
        return Quickshell.iconPath(icon, true);
    }

    function safeMarkup(value: string): string {
        if (!value)
            return "";
        return value.replace(/<[^>]*>/g, tag => {
            return /^<\/?(?:b|i|u)>$/i.test(tag) || /^<br\s*\/?>$/i.test(tag) ? tag : "";
        });
    }

    function timestamp(): string {
        return entry && entry.receivedAt > 0
            ? Qt.formatDateTime(new Date(entry.receivedAt), "HH:mm")
            : "";
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                root.notificationState.dismissEntry(root.entry);
            else
                root.notificationState.invokeDefault(root.entry);
        }
    }

    Row {
        id: contentRow

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 15
        }
        spacing: root.iconSource ? 12 : 0

        Item {
            width: root.iconSource ? 48 : 0
            height: 48
            visible: width > 0

            IconImage {
                anchors.fill: parent
                source: root.iconSource
                implicitSize: 48
            }
        }

        Column {
            id: textColumn

            width: contentRow.width - (root.iconSource ? 60 : 0)
            spacing: 5

            Row {
                width: parent.width
                spacing: 8

                Text {
                    width: parent.width - closeButton.width - timeLabel.width - parent.spacing * 2
                    text: root.groupAppName || (root.notification ? (root.notification.appName || root.notification.desktopEntry || "Unknown application") : "")
                    color: root.theme.foregroundMuted
                    font.family: root.theme.textFont
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    id: timeLabel

                    visible: !root.toastMode
                    text: root.timestamp()
                    color: root.theme.foregroundMuted
                    font.family: root.theme.textFont
                    font.pixelSize: 11
                }

                Rectangle {
                    id: closeButton

                    width: 22
                    height: 22
                    color: closeMouse.containsMouse ? root.theme.hoverLayer : "transparent"
                    radius: 6

                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: root.theme.foregroundMuted
                        font.family: root.theme.textFont
                        font.pixelSize: 17
                    }

                    MouseArea {
                        id: closeMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.notificationState.dismissEntry(root.entry)
                    }
                }
            }

            Text {
                width: parent.width
                text: {
                    const summary = root.notification ? root.notification.summary : "";
                    return root.groupCount > 1 ? `${summary} · ${root.groupCount}` : summary;
                }
                color: root.theme.foreground
                font.family: root.theme.textFont
                font.pixelSize: root.toastMode ? 14 : 15
                font.weight: Font.DemiBold
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: root.toastMode ? 2 : 4
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: text.length > 0
                text: root.safeMarkup(root.notification ? root.notification.body : "")
                color: root.theme.foregroundMuted
                font.family: root.theme.textFont
                font.pixelSize: root.toastMode ? 13 : 14
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: root.toastMode ? 3 : 12
                elide: Text.ElideRight
            }

            Rectangle {
                width: parent.width
                height: 5
                visible: root.progressValue >= 0
                color: root.theme.surfaceContainer
                radius: 3

                Rectangle {
                    width: parent.width * root.progressValue / 100
                    height: parent.height
                    color: root.theme.primary
                    radius: parent.radius
                }
            }

            Row {
                width: parent.width
                spacing: 6
                visible: root.explicitActions.length > 0

                Repeater {
                    model: root.explicitActions.slice(0, root.toastMode ? 2 : 4)

                    Rectangle {
                        id: actionButton

                        required property var modelData
                        width: Math.min(actionLabel.implicitWidth + 20, textColumn.width / Math.max(1, root.explicitActions.length) - 4)
                        height: 28
                        color: actionMouse.containsMouse ? root.theme.hoverLayer : root.theme.surfaceContainer
                        border.color: root.theme.outlineVariant
                        border.width: 1
                        radius: 7

                        Text {
                            id: actionLabel

                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, actionButton.width - 12)
                            text: actionButton.modelData.text
                            color: root.theme.foreground
                            font.family: root.theme.textFont
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            id: actionMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.notificationState.invokeAction(actionButton.modelData)
                        }
                    }
                }
            }
        }
    }
}
