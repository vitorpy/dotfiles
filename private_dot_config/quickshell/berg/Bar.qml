import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Widgets
import "components"

Scope {
    id: root

    required property var modelData
    required property var barState
    property bool previewMode: false

    Theme {
        id: theme
    }

    function volumePercent(node: var): int {
        if (!node || !node.audio)
            return 0;
        return Math.round(node.audio.volume * 100);
    }

    function speakerGlyph(): string {
        const sink = root.barState.audioSink;
        if (!sink || !sink.audio || sink.audio.muted)
            return theme.speakerMuted;
        return sink.audio.volume < 0.5 ? theme.speakerLow : theme.speakerHigh;
    }

    function microphoneGlyph(): string {
        const source = root.barState.audioSource;
        if (!source || !source.audio || source.audio.muted)
            return theme.microphoneMuted;
        return theme.microphone;
    }

    function audioTooltip(node: var, label: string): string {
        if (!node || !node.audio)
            return `${label}: unavailable`;

        const description = node.description || node.name || label;
        const muted = node.audio.muted ? " · muted" : "";
        return `${description}\n${volumePercent(node)}%${muted}`;
    }

    function firstCharacter(value: string): string {
        if (!value)
            return "";

        const firstCodeUnit = value.charCodeAt(0);
        const characterLength = firstCodeUnit >= 0xD800 && firstCodeUnit <= 0xDBFF ? 2 : 1;
        return value.substring(0, characterLength);
    }

    function textAfterGlyph(value: string): string {
        if (!value)
            return "";
        const separator = value.indexOf(" ");
        return separator >= 0 ? value.substring(separator + 1) : "";
    }

    function batteryPercent(): int {
        const value = UPower.displayDevice.percentage;
        if (!Number.isFinite(value))
            return 0;
        return Math.round(value <= 1 ? value * 100 : value);
    }

    function batteryIsCharging(): bool {
        const batteryState = UPower.displayDevice.state;
        return batteryState === UPowerDeviceState.Charging || batteryState === UPowerDeviceState.PendingCharge;
    }

    function batteryGlyph(): string {
        if (batteryIsCharging())
            return theme.batteryCharging;

        const percentage = batteryPercent();
        if (percentage < 20)
            return theme.batteryLevels[0];
        if (percentage < 40)
            return theme.batteryLevels[1];
        if (percentage < 60)
            return theme.batteryLevels[2];
        if (percentage < 80)
            return theme.batteryLevels[3];
        return theme.batteryLevels[4];
    }

    function durationLabel(seconds: real): string {
        if (!Number.isFinite(seconds) || seconds <= 0)
            return "";

        const totalMinutes = Math.round(seconds / 60);
        const hours = Math.floor(totalMinutes / 60);
        const minutes = totalMinutes % 60;
        return hours > 0 ? `${hours}h ${minutes}m` : `${minutes}m`;
    }

    function batteryTooltip(): string {
        const battery = UPower.displayDevice;
        const stateName = UPowerDeviceState.toString(battery.state);
        const estimate = batteryIsCharging() ? durationLabel(battery.timeToFull) : durationLabel(battery.timeToEmpty);
        const estimateLabel = batteryIsCharging() ? "until full" : "remaining";
        return estimate ? `Battery · ${stateName}\n${batteryPercent()}% · ${estimate} ${estimateLabel}` : `Battery · ${stateName}\n${batteryPercent()}%`;
    }

    PanelWindow {
        id: panel

        screen: root.modelData
        color: "transparent"
        implicitHeight: 68
        aboveWindows: true
        focusable: false
        exclusiveZone: root.previewMode ? 0 : 68

        anchors {
            top: true
            left: true
            right: true
        }

        Item {
            id: layoutRoot
            anchors.fill: parent

            Row {
                id: leftRow

                anchors {
                    left: parent.left
                    leftMargin: 16
                    verticalCenter: parent.verticalCenter
                }

                spacing: 16

                BarCell {
                    theme: theme
                    visible: root.barState.updatesData.text.length > 0
                    horizontalPadding: 16
                    backgroundColor: theme.surfaceContainerHigh
                    cornerRadius: 12
                    tooltipText: root.barState.updatesData.tooltip || ""

                    MetricLabel {
                        theme: theme
                        glyph: root.firstCharacter(root.barState.updatesData.text || "")
                        label: root.textAfterGlyph(root.barState.updatesData.text || "")
                    }
                }

                BarCell {
                    theme: theme
                    visible: root.barState.rebootData.text.length > 0
                    horizontalPadding: 16
                    backgroundColor: theme.surfaceContainerHigh
                    cornerRadius: 12
                    tooltipText: root.barState.rebootData.tooltip || ""

                    MetricLabel {
                        theme: theme
                        glyph: root.firstCharacter(root.barState.rebootData.text || "")
                    }
                }
            }

            Rectangle {
                id: centerGroup

                anchors {
                    horizontalCenter: parent.horizontalCenter
                    verticalCenter: parent.verticalCenter
                }

                width: clockCell.implicitWidth + 16
                height: 54
                color: theme.surfaceContainerHigh
                radius: 12

                BarCell {
                    id: clockCell

                    anchors.centerIn: parent
                    theme: theme
                    tooltipText: root.barState.clockData.tooltip || ""

                    MetricLabel {
                        theme: theme
                        label: root.barState.clockData.text || ""
                    }
                }
            }

            Rectangle {
                id: rightGroup

                anchors {
                    right: parent.right
                    rightMargin: 16
                    verticalCenter: parent.verticalCenter
                }

                width: rightRow.implicitWidth + 16
                height: 54
                color: theme.surfaceContainerHigh
                radius: 12

                Row {
                    id: rightRow

                    x: 8
                    anchors.verticalCenter: parent.verticalCenter

                    BarCell {
                        theme: theme
                        minimumWidth: 54
                        interactive: true
                        tooltipText: root.audioTooltip(root.barState.audioSink, "Audio output")
                        onLeftClicked: root.barState.toggleAudioMute(root.barState.audioSink)
                        onRightClicked: root.barState.togglePwCenter()
                        onWheelUp: root.barState.changeAudioVolume(root.barState.audioSink, 0.05)
                        onWheelDown: root.barState.changeAudioVolume(root.barState.audioSink, -0.05)

                        MetricLabel {
                            theme: theme
                            glyph: root.speakerGlyph()
                            label: `${root.volumePercent(root.barState.audioSink)}%`
                        }
                    }

                    BarCell {
                        theme: theme
                        minimumWidth: 54
                        separator: true
                        interactive: true
                        tooltipText: root.audioTooltip(root.barState.audioSource, "Audio input")
                        onLeftClicked: root.barState.toggleAudioMute(root.barState.audioSource)
                        onRightClicked: root.barState.togglePwCenter()
                        onWheelUp: root.barState.changeAudioVolume(root.barState.audioSource, 0.05)
                        onWheelDown: root.barState.changeAudioVolume(root.barState.audioSource, -0.05)

                        MetricLabel {
                            theme: theme
                            glyph: root.microphoneGlyph()
                            label: `${root.volumePercent(root.barState.audioSource)}%`
                        }
                    }

                    BarCell {
                        theme: theme
                        minimumWidth: 54
                        separator: true
                        interactive: true
                        tooltipText: `Brightness: ${root.barState.brightnessData.percent || 0}%`
                        onLeftClicked: root.barState.changeBrightness("100%")
                        onWheelUp: root.barState.changeBrightness("+5%")
                        onWheelDown: root.barState.changeBrightness("5%-")

                        MetricLabel {
                            theme: theme
                            glyph: theme.brightness
                            label: `${root.barState.brightnessData.percent || 0}%`
                        }
                    }

                    BarCell {
                        theme: theme
                        visible: (root.barState.profileData.text || "").length > 0
                        minimumWidth: 100
                        separator: true
                        interactive: true
                        tooltipText: root.barState.profileData.tooltip || ""
                        onLeftClicked: root.barState.cyclePowerProfile()

                        MetricLabel {
                            theme: theme
                            label: root.barState.profileData.text || ""
                        }
                    }

                    BarCell {
                        theme: theme
                        visible: UPower.displayDevice.ready && UPower.displayDevice.isLaptopBattery
                        minimumWidth: 34
                        separator: true
                        tooltipText: root.batteryTooltip()
                        backgroundColor: root.batteryPercent() <= 5 ? theme.error : "transparent"

                        MetricLabel {
                            theme: theme
                            glyph: root.batteryGlyph()
                            label: `${root.batteryPercent()}%`
                            glyphAfter: true
                            foreground: root.batteryPercent() <= 5 ? theme.onErrorColor : (root.batteryPercent() <= 10 ? theme.error : theme.foreground)
                        }
                    }

                    BarCell {
                        theme: theme
                        minimumWidth: 48
                        separator: true
                        tooltipText: `CPU utilization: ${root.barState.systemStats.cpuUsage}%`

                        MetricLabel {
                            theme: theme
                            glyph: theme.cpu
                            label: `${root.barState.systemStats.cpuUsage}%`
                        }
                    }

                    BarCell {
                        theme: theme
                        minimumWidth: 56
                        separator: true
                        tooltipText: `Temperature: ${root.barState.systemStats.temperatureC} °C`

                        MetricLabel {
                            theme: theme
                            glyph: theme.temperature
                            label: `${root.barState.systemStats.temperatureC} °C`
                        }
                    }

                    BarCell {
                        theme: theme
                        minimumWidth: 44
                        horizontalPadding: 0
                        separator: true
                        interactive: true
                        tooltipText: "Keyboard layout"
                        onLeftClicked: root.barState.toggleKeyboard()

                        MetricLabel {
                            theme: theme
                            label: root.barState.keyboardData.text || "?"
                        }
                    }

                    BarCell {
                        theme: theme
                        minimumWidth: 36
                        separator: true

                        Row {
                            spacing: 8

                            Repeater {
                                model: SystemTray.items

                                Item {
                                    id: trayItem

                                    required property var modelData
                                    width: 16
                                    height: 16

                                    readonly property string tooltipText: {
                                        const title = modelData.tooltipTitle || modelData.title || "";
                                        const description = modelData.tooltipDescription || "";
                                        return title && description ? `${title}\n${description}` : (title || description);
                                    }

                                    IconImage {
                                        anchors.fill: parent
                                        source: trayItem.modelData.icon
                                        implicitSize: 16
                                    }

                                    MouseArea {
                                        id: trayMouseArea

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                                        onClicked: mouse => {
                                            const point = trayItem.mapToItem(panel.contentItem, mouse.x, mouse.y + trayItem.height);
                                            if (mouse.button === Qt.RightButton && trayItem.modelData.hasMenu)
                                                trayItem.modelData.display(panel, point.x, point.y);
                                            else if (mouse.button === Qt.MiddleButton)
                                                trayItem.modelData.secondaryActivate();
                                            else if (trayItem.modelData.onlyMenu && trayItem.modelData.hasMenu)
                                                trayItem.modelData.display(panel, point.x, point.y);
                                            else
                                                trayItem.modelData.activate();
                                        }

                                        onWheel: wheel => trayItem.modelData.scroll(wheel.angleDelta.y, false)
                                    }

                                    ToolTip {
                                        id: trayTooltip

                                        visible: trayItem.tooltipText.length > 0 && trayMouseArea.containsMouse
                                        text: trayItem.tooltipText
                                        delay: 500
                                        timeout: -1
                                        y: trayItem.height + 8
                                        popupType: Popup.Window
                                        leftPadding: 14
                                        rightPadding: 14
                                        topPadding: 12
                                        bottomPadding: 12

                                        contentItem: Text {
                                            text: trayTooltip.text
                                            color: theme.foreground
                                            font.family: theme.textFont
                                            font.pixelSize: theme.tooltipFontSize
                                            font.weight: Font.Medium
                                        }

                                        background: Rectangle {
                                            color: theme.tooltipSurface
                                            border.color: theme.outlineVariant
                                            border.width: 1
                                            radius: 12
                                        }
                                    }
                                }
                            }
                        }
                    }

                    BarCell {
                        theme: theme
                        minimumWidth: 44
                        horizontalPadding: 0
                        separator: true
                        interactive: true
                        tooltipText: root.barState.dndData.tooltip || ""
                        onLeftClicked: root.barState.toggleDnd()
                        onRightClicked: root.barState.dismissNotifications()

                        MetricLabel {
                            theme: theme
                            glyph: root.firstCharacter(root.barState.dndData.text || "")
                        }
                    }

                    BarCell {
                        theme: theme
                        minimumWidth: 44
                        horizontalPadding: 0
                        separator: true
                        interactive: true
                        onLeftClicked: powerMenu.open()

                        MetricLabel {
                            theme: theme
                            glyph: theme.power
                        }
                    }
                }
            }

            Popup {
                id: powerMenu

                parent: layoutRoot
                x: layoutRoot.width - width - 16
                y: 69
                width: 180
                height: powerMenuColumn.implicitHeight
                padding: 0
                modal: false
                focus: true
                popupType: Popup.Window
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

                background: Rectangle {
                    color: theme.surfaceContainerHigh
                    radius: 12
                }

                contentItem: Column {
                    id: powerMenuColumn

                    Repeater {
                        model: [
                            {
                                "label": "Logout",
                                "action": "logout"
                            },
                            {
                                "label": "Reboot",
                                "action": "reboot"
                            },
                            {
                                "label": "Shutdown",
                                "action": "poweroff"
                            }
                        ]

                        Item {
                            required property var modelData
                            width: powerMenu.width
                            height: 44

                            Rectangle {
                                anchors.fill: parent
                                color: powerMenuMouse.containsMouse ? theme.hoverLayer : "transparent"
                                radius: 8
                            }

                            Text {
                                anchors {
                                    left: parent.left
                                    leftMargin: 12
                                    verticalCenter: parent.verticalCenter
                                }

                                text: modelData.label
                                color: theme.foreground
                                font.family: theme.textFont
                                font.pixelSize: theme.fontSize
                                font.weight: Font.Medium
                            }

                            MouseArea {
                                id: powerMenuMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    powerMenu.close();
                                    root.barState.runSessionAction(modelData.action);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
