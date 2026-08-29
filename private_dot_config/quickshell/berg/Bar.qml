import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Wayland
import Quickshell.Widgets
import "components"
import "GmailUnread.js" as GmailUnread

Scope {
    id: root

    required property var modelData
    required property var barState
    property bool previewMode: false
    readonly property var palette: theme

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
        if (!sink || !sink.audio)
            return theme.speakerMuted;
        if (root.barState.headphonesActive)
            return theme.headphones;
        if (sink.audio.muted)
            return theme.speakerMuted;
        return sink.audio.volume < 0.5 ? theme.speakerLow : theme.speakerHigh;
    }

    function microphoneGlyph(): string {
        const source = root.barState.audioSource;
        if (!source || !source.audio || source.audio.muted)
            return theme.microphoneMuted;
        return theme.microphone;
    }

    function audioTooltip(node: var, label: string, showBattery: bool, deviceBatteryPercent: int): string {
        if (!node || !node.audio)
            return `${label}: unavailable`;

        const description = node.description || node.name || label;
        const muted = node.audio.muted ? " · muted" : "";
        const lines = [description, `${volumePercent(node)}%${muted}`];
        if (showBattery)
            lines.push(`Battery: ${deviceBatteryPercent}%`);
        return lines.join("\n");
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

    function unhealthy(state: var): bool {
        return state && (state.health === "stale" || state.health === "error");
    }

    function healthTooltip(base: string, state: var): string {
        if (!unhealthy(state))
            return base;

        const lines = [base];
        if (state.lastError && base.indexOf(state.lastError) < 0)
            lines.push(state.lastError);
        if (state.lastSuccess)
            lines.push(`Last successful refresh: ${Qt.formatDateTime(state.lastSuccess, "dd.MM HH:mm:ss")}`);
        return lines.filter(line => line && line.length > 0).join("\n");
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

    function syncPowerMenu(): void {
        const shouldOpen = root.barState.panels.isOpen("power", root.modelData.name);
        if (shouldOpen && !powerMenu.visible)
            powerMenu.open();
        else if (!shouldOpen && powerMenu.visible)
            powerMenu.close();
    }

    Connections {
        target: root.barState.panels

        function onActivePanelChanged(): void {
            root.syncPowerMenu();
        }

        function onScreenNameChanged(): void {
            root.syncPowerMenu();
        }
    }

    Component.onCompleted: syncPowerMenu()

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

        IdleInhibitor {
            window: panel
            enabled: root.barState.stayAwake.enabled
                && panel.visible
                && !root.previewMode
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
                    visible: root.barState.gmailUnread.visible
                    horizontalPadding: 6
                    contentSpacing: 2
                    backgroundColor: theme.surfaceContainerHigh
                    cornerRadius: 12

                    Repeater {
                        model: root.barState.gmailUnread.accounts

                        delegate: BarCell {
                            id: gmailAccountCell

                            required property var modelData
                            required property int index
                            readonly property color accountColor: root.palette.gmailAccountColor(modelData.browserIndex)

                            theme: root.palette
                            visible: GmailUnread.hasUnread(modelData.total)
                            interactive: true
                            cellHeight: 30
                            horizontalPadding: 8
                            separator: GmailUnread.hasPreviousUnreadAccount(
                                root.barState.gmailUnread.accounts,
                                index
                            )
                            backgroundColor: "transparent"
                            hoverColor: root.palette.hoverLayer
                            cornerRadius: 8
                            tooltipText: GmailUnread.accountTooltip(
                                modelData,
                                root.barState.gmailUnread.countField
                            )
                            onLeftClicked: Quickshell.execDetached([
                                "/usr/bin/xdg-open",
                                GmailUnread.accountInboxUrl(modelData)
                            ])
                            onRightClicked: root.barState.refreshGmailUnread()

                            MetricLabel {
                                theme: gmailAccountCell.theme
                                glyph: gmailAccountCell.theme.mail
                                label: GmailUnread.badgeText(gmailAccountCell.modelData.total)
                                foreground: root.unhealthy(root.barState.gmailUnread)
                                    ? gmailAccountCell.theme.error
                                    : gmailAccountCell.accountColor
                                warning: root.unhealthy(root.barState.gmailUnread)
                            }
                        }
                    }

                    BarCell {
                        theme: root.palette
                        visible: root.barState.gmailUnread.total === 0
                            && root.unhealthy(root.barState.gmailUnread)
                        interactive: true
                        cellHeight: 30
                        horizontalPadding: 8
                        backgroundColor: "transparent"
                        cornerRadius: 8
                        tooltipText: root.barState.gmailUnread.tooltip
                        onLeftClicked: root.barState.refreshGmailUnread()

                        MetricLabel {
                            theme: root.palette
                            glyph: root.palette.mail
                            foreground: root.palette.error
                            warning: true
                        }
                    }
                }

                BarCell {
                    theme: theme
                    visible: root.barState.updates.visible
                    horizontalPadding: 16
                    backgroundColor: theme.surfaceContainerHigh
                    cornerRadius: 12
                    tooltipText: root.healthTooltip(root.barState.updates.tooltip, root.barState.updates)

                    MetricLabel {
                        theme: theme
                        glyph: root.barState.updates.total > 0 ? theme.updates : ""
                        label: root.barState.updates.total > 0 ? root.barState.updates.total.toString() : ""
                        foreground: root.unhealthy(root.barState.updates) ? theme.error : theme.foreground
                        warning: root.unhealthy(root.barState.updates)
                    }
                }

                BarCell {
                    theme: theme
                    visible: root.barState.reboot.visible
                    horizontalPadding: 16
                    backgroundColor: theme.surfaceContainerHigh
                    cornerRadius: 12
                    tooltipText: root.healthTooltip(root.barState.reboot.tooltip, root.barState.reboot)

                    MetricLabel {
                        theme: theme
                        glyph: root.barState.reboot.rebootRequired ? theme.reboot : ""
                        foreground: root.unhealthy(root.barState.reboot) ? theme.error : theme.foreground
                        warning: root.unhealthy(root.barState.reboot)
                    }
                }

                BarCell {
                    theme: theme
                    visible: root.barState.stayAwake.enabled
                    interactive: true
                    horizontalPadding: 16
                    backgroundColor: theme.surfaceContainerHigh
                    cornerRadius: 12
                    tooltipText: "Stay awake is active\nClick to allow idle actions"
                    onLeftClicked: root.barState.toggleStayAwake(root.modelData.name)

                    MetricLabel {
                        theme: theme
                        label: "AWAKE"
                        foreground: theme.primary
                    }
                }

                BarCell {
                    theme: theme
                    visible: root.barState.media.visible
                    interactive: true
                    horizontalPadding: 12
                    contentSpacing: 8
                    backgroundColor: theme.surfaceContainerHigh
                    cornerRadius: 12
                    tooltipText: root.barState.media.tooltip
                    onLeftClicked: root.barState.runMediaAction("play-pause", root.modelData.name)
                    onMiddleClicked: root.barState.runMediaAction("next", root.modelData.name)
                    onRightClicked: root.barState.cycleMediaSource(1, root.modelData.name)
                    onWheelUp: root.barState.runMediaAction("previous", root.modelData.name)
                    onWheelDown: root.barState.runMediaAction("next", root.modelData.name)

                    Text {
                        text: root.barState.media.playing ? "⏸" : "▶"
                        color: root.barState.media.playing ? theme.primary : theme.foregroundMuted
                        font.family: theme.textFont
                        font.pixelSize: theme.fontSize
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: root.barState.media.barLabel
                        width: Math.min(180, implicitWidth)
                        elide: Text.ElideRight
                        color: theme.foreground
                        font.family: theme.textFont
                        font.pixelSize: theme.fontSize
                        font.weight: Font.Medium
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
                    interactive: true
                    tooltipText: root.healthTooltip(root.barState.clock.compactTooltip, root.barState.clock)
                    onLeftClicked: root.barState.toggleClockPanel(root.modelData.name)
                    onRightClicked: root.barState.refreshClock()

                    MetricLabel {
                        theme: theme
                        label: root.barState.clock.text
                        foreground: root.unhealthy(root.barState.clock) ? theme.error : theme.foreground
                        warning: root.unhealthy(root.barState.clock)
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
                        tooltipText: root.audioTooltip(
                            root.barState.audioSink,
                            "Audio output",
                            root.barState.audioSinkBatteryAvailable,
                            root.barState.audioSinkBatteryPercent
                        )
                        onLeftClicked: root.barState.toggleAudioMute(root.barState.audioSink, false, root.modelData.name)
                        onRightClicked: root.barState.toggleAudioPanel(root.modelData.name)
                        onWheelUp: root.barState.changeAudioVolume(root.barState.audioSink, 0.05, false, root.modelData.name)
                        onWheelDown: root.barState.changeAudioVolume(root.barState.audioSink, -0.05, false, root.modelData.name)

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
                        tooltipText: root.audioTooltip(root.barState.audioSource, "Audio input", false, 0)
                        onLeftClicked: root.barState.toggleAudioMute(root.barState.audioSource, true, root.modelData.name)
                        onRightClicked: root.barState.toggleAudioPanel(root.modelData.name)
                        onWheelUp: root.barState.changeAudioVolume(root.barState.audioSource, 0.05, true, root.modelData.name)
                        onWheelDown: root.barState.changeAudioVolume(root.barState.audioSource, -0.05, true, root.modelData.name)

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
                        tooltipText: root.healthTooltip(
                            root.barState.brightness.hasValue
                                ? `Brightness: ${root.barState.brightness.percent}%`
                                : "Brightness: unavailable",
                            root.barState.brightness
                        )
                        onLeftClicked: root.barState.changeBrightness("100%", root.modelData.name)
                        onWheelUp: root.barState.changeBrightness("+5%", root.modelData.name)
                        onWheelDown: root.barState.changeBrightness("5%-", root.modelData.name)

                        MetricLabel {
                            theme: theme
                            glyph: theme.brightness
                            label: root.barState.brightness.hasValue ? `${root.barState.brightness.percent}%` : "—"
                            foreground: root.unhealthy(root.barState.brightness) ? theme.error : theme.foreground
                            warning: root.unhealthy(root.barState.brightness)
                        }
                    }

                    BarCell {
                        theme: theme
                        minimumWidth: 100
                        separator: true
                        interactive: true
                        tooltipText: root.healthTooltip(root.barState.powerProfile.tooltip, root.barState.powerProfile)
                        onLeftClicked: root.barState.cyclePowerProfile(root.modelData.name)

                        MetricLabel {
                            theme: theme
                            label: root.barState.powerProfile.label
                            foreground: root.unhealthy(root.barState.powerProfile) ? theme.error : theme.foreground
                            warning: root.unhealthy(root.barState.powerProfile)
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
                        visible: root.barState.systemStats.cpuNeedsAttention
                        minimumWidth: 48
                        separator: true
                        tooltipText: root.barState.systemStats.cpuError
                            ? `CPU utilization: ${root.barState.systemStats.cpuHasValue ? root.barState.systemStats.cpuUsage + "%" : "unavailable"}\n${root.barState.systemStats.cpuError}`
                            : `CPU utilization: ${root.barState.systemStats.cpuUsage}%`

                        MetricLabel {
                            theme: theme
                            glyph: theme.cpu
                            label: root.barState.systemStats.cpuHasValue ? `${root.barState.systemStats.cpuUsage}%` : "—"
                            foreground: root.barState.systemStats.cpuError ? theme.error : theme.foreground
                            warning: root.barState.systemStats.cpuError.length > 0
                        }
                    }

                    BarCell {
                        theme: theme
                        visible: root.barState.systemStats.temperatureNeedsAttention
                        minimumWidth: 56
                        separator: true
                        tooltipText: root.barState.systemStats.temperatureError
                            ? `Temperature: ${root.barState.systemStats.temperatureHasValue ? root.barState.systemStats.temperatureC + " °C" : "unavailable"}\n${root.barState.systemStats.temperatureError}`
                            : `Temperature: ${root.barState.systemStats.temperatureC} °C`

                        MetricLabel {
                            theme: theme
                            glyph: theme.temperature
                            label: root.barState.systemStats.temperatureHasValue ? `${root.barState.systemStats.temperatureC} °C` : "—"
                            foreground: root.barState.systemStats.temperatureError ? theme.error : theme.foreground
                            warning: root.barState.systemStats.temperatureError.length > 0
                        }
                    }

                    BarCell {
                        theme: theme
                        minimumWidth: 44
                        horizontalPadding: 0
                        separator: true
                        interactive: true
                        tooltipText: root.healthTooltip("Keyboard layout", root.barState.keyboard)
                        onLeftClicked: root.barState.toggleKeyboard()

                        MetricLabel {
                            theme: theme
                            label: root.barState.keyboard.layout
                            foreground: root.unhealthy(root.barState.keyboard) ? theme.error : theme.foreground
                            warning: root.unhealthy(root.barState.keyboard)
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
                        tooltipText: root.barState.notifications.tooltip
                        onLeftClicked: root.barState.toggleNotificationCenter(root.modelData.name)
                        onRightClicked: root.barState.toggleDnd()

                        MetricLabel {
                            theme: theme
                            glyph: root.barState.notifications.dnd ? theme.dndEnabled : theme.dndDisabled
                            label: root.barState.notifications.dnd ? "" : root.barState.notifications.badgeText
                            foreground: theme.foreground
                        }
                    }

                    BarCell {
                        theme: theme
                        minimumWidth: 44
                        horizontalPadding: 0
                        separator: true
                        interactive: true
                        onLeftClicked: root.barState.togglePowerMenu(root.modelData.name)

                        MetricLabel {
                            theme: theme
                            glyph: theme.power
                        }
                    }
                }
            }

            NotificationCenter {
                screen: root.modelData
                theme: root.palette
                notificationState: root.barState.notifications
            }

            ClockPanel {
                screen: root.modelData
                theme: root.palette
                clockState: root.barState.clock
            }

            AudioPanel {
                modelData: root.modelData
                theme: root.palette
                audioState: root.barState.audioDevices
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

                onClosed: {
                    if (root.barState.panels.isOpen("power", root.modelData.name))
                        root.barState.panels.closePanel("power");
                }

                background: Rectangle {
                    color: theme.surfaceContainerHigh
                    radius: 12
                }

                contentItem: Column {
                    id: powerMenuColumn

                    Repeater {
                        model: [
                            {
                                "label": root.barState.stayAwake.enabled ? "Allow sleep" : "Stay awake",
                                "action": "toggle-stay-awake"
                            },
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
                                    if (modelData.action === "toggle-stay-awake")
                                        root.barState.toggleStayAwake(root.modelData.name);
                                    else
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
