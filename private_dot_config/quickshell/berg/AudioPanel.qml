pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

PanelWindow {
    id: root

    required property var modelData
    required property var theme
    required property var audioState

    readonly property string screenName: screen ? screen.name : ""

    screen: root.modelData
    visible: audioState.panelOpen && audioState.popouts.screenName === screenName
    color: "transparent"
    implicitWidth: 440
    implicitHeight: Math.min(560, Math.max(260, deviceColumn.implicitHeight + 98))
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
        radius: 14

        Rectangle {
            anchors {
                left: parent.left
                top: parent.top
                bottom: headerDivider.top
            }
            width: 4
            color: root.theme.primary
            radius: 2
        }

        Item {
            id: header

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 16
            }
            height: 44

            Text {
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }
                text: "Audio routes"
                color: root.theme.foreground
                font.family: root.theme.textFont
                font.pixelSize: 20
                font.weight: Font.DemiBold
            }

            Rectangle {
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                width: 34
                height: 34
                color: closeMouse.containsMouse ? root.theme.hoverLayer : root.theme.surfaceContainer
                border.color: root.theme.outlineVariant
                border.width: 1
                radius: 9

                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: root.theme.foreground
                    font.family: root.theme.textFont
                    font.pixelSize: 19
                }

                MouseArea {
                    id: closeMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.audioState.closePanel()
                }
            }
        }

        Rectangle {
            id: headerDivider

            anchors {
                left: parent.left
                right: parent.right
                top: header.bottom
                topMargin: 10
            }
            height: 1
            color: root.theme.outlineVariant
        }

        Flickable {
            id: deviceFlickable

            anchors {
                left: parent.left
                right: parent.right
                top: headerDivider.bottom
                bottom: parent.bottom
                margins: 16
            }
            contentWidth: width
            contentHeight: deviceColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: deviceColumn

                width: deviceFlickable.width
                spacing: 8

                Text {
                    text: "OUTPUT"
                    color: root.theme.primary
                    font.family: root.theme.textFont
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }

                Text {
                    visible: root.audioState.sinkDevices.length === 0
                    text: "No output devices detected"
                    color: root.theme.foregroundMuted
                    font.family: root.theme.textFont
                    font.pixelSize: 14
                }

                Repeater {
                    model: root.audioState.sinkDevices

                    Rectangle {
                        id: outputDevice

                        required property var modelData

                        width: deviceColumn.width
                        height: 54
                        color: outputMouse.containsMouse
                            ? root.theme.hoverLayer
                            : (modelData.active ? root.theme.surfaceContainer : "transparent")
                        border.color: modelData.active ? root.theme.primary : root.theme.outlineVariant
                        border.width: 1
                        radius: 10
                        opacity: root.audioState.switching ? 0.6 : 1

                        Text {
                            anchors {
                                left: parent.left
                                leftMargin: 14
                                right: outputBadge.left
                                rightMargin: 10
                                verticalCenter: parent.verticalCenter
                            }
                            text: outputDevice.modelData.label
                            color: root.theme.foreground
                            font.family: root.theme.textFont
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        Text {
                            id: outputBadge

                            anchors {
                                right: parent.right
                                rightMargin: 14
                                verticalCenter: parent.verticalCenter
                            }
                            text: outputDevice.modelData.active
                                ? "DEFAULT"
                                : (outputDevice.modelData.jabra ? "JABRA" : "")
                            color: root.theme.primary
                            font.family: root.theme.textFont
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }

                        MouseArea {
                            id: outputMouse

                            anchors.fill: parent
                            enabled: !root.audioState.switching
                            hoverEnabled: true
                            onClicked: root.audioState.selectNode(
                                "sink",
                                outputDevice.modelData.node,
                                root.screenName
                            )
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: root.theme.outlineVariant
                }

                Text {
                    text: "INPUT"
                    color: root.theme.primary
                    font.family: root.theme.textFont
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }

                Text {
                    visible: root.audioState.sourceDevices.length === 0
                    text: "No input devices detected"
                    color: root.theme.foregroundMuted
                    font.family: root.theme.textFont
                    font.pixelSize: 14
                }

                Repeater {
                    model: root.audioState.sourceDevices

                    Rectangle {
                        id: inputDevice

                        required property var modelData

                        width: deviceColumn.width
                        height: 54
                        color: inputMouse.containsMouse
                            ? root.theme.hoverLayer
                            : (modelData.active ? root.theme.surfaceContainer : "transparent")
                        border.color: modelData.active ? root.theme.primary : root.theme.outlineVariant
                        border.width: 1
                        radius: 10
                        opacity: root.audioState.switching ? 0.6 : 1

                        Text {
                            anchors {
                                left: parent.left
                                leftMargin: 14
                                right: inputBadge.left
                                rightMargin: 10
                                verticalCenter: parent.verticalCenter
                            }
                            text: inputDevice.modelData.label
                            color: root.theme.foreground
                            font.family: root.theme.textFont
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        Text {
                            id: inputBadge

                            anchors {
                                right: parent.right
                                rightMargin: 14
                                verticalCenter: parent.verticalCenter
                            }
                            text: inputDevice.modelData.active
                                ? "DEFAULT"
                                : (inputDevice.modelData.jabra ? "JABRA" : "")
                            color: root.theme.primary
                            font.family: root.theme.textFont
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }

                        MouseArea {
                            id: inputMouse

                            anchors.fill: parent
                            enabled: !root.audioState.switching
                            hoverEnabled: true
                            onClicked: root.audioState.selectNode(
                                "source",
                                inputDevice.modelData.node,
                                root.screenName
                            )
                        }
                    }
                }

                Text {
                    visible: root.audioState.lastError.length > 0
                    width: parent.width
                    text: root.audioState.lastError
                    color: root.theme.error
                    font.family: root.theme.textFont
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }
            }
        }
    }
}
