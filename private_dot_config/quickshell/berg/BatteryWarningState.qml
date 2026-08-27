import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "BatteryWarning.js" as BatteryWarning

Scope {
    id: root

    readonly property int warningThreshold: 10
    readonly property int resetThreshold: 15
    readonly property var battery: UPower.displayDevice
    readonly property int percentage: BatteryWarning.normalizedPercentage(battery.percentage)

    property string health: "ready"
    property string lastError: ""
    property var lastSuccess: null

    function check(): void {
        const available = battery.ready && battery.isLaptopBattery;
        const discharging = battery.state === UPowerDeviceState.Discharging;
        const state = BatteryWarning.evaluate(
            battery.percentage,
            available,
            UPower.onBattery,
            discharging,
            persisted.notifiedLowBattery,
            warningThreshold,
            resetThreshold
        );

        if (persisted.notifiedLowBattery !== state.notified)
            persisted.notifiedLowBattery = state.notified;
        if (state.notify)
            sendWarning(state.percentage);
    }

    function sendWarning(level: int): void {
        warning.command = [
            "/usr/bin/notify-send",
            "--app-name=Berg",
            "--urgency=critical",
            "--icon=battery-caution-symbolic",
            "--hint=string:x-dunst-stack-tag:berg-low-battery",
            "Low battery",
            `${level}% remaining. Connect power soon.`
        ];
        warning.refresh();
    }

    function status(): string {
        return JSON.stringify({
            percentage: percentage,
            onBattery: UPower.onBattery,
            discharging: battery.state === UPowerDeviceState.Discharging,
            notified: persisted.notifiedLowBattery,
            health: health,
            lastError: lastError
        });
    }

    PersistentProperties {
        id: persisted

        reloadableId: "berg-low-battery-warning"
        property bool notifiedLowBattery: false
    }

    ProcessJob {
        id: warning

        runOnStart: false
        timeoutMs: 5000
        onSucceeded: {
            root.health = "ready";
            root.lastError = "";
            root.lastSuccess = new Date();
        }
        onFailed: (message, exitCode, output, errorOutput) => {
            root.health = root.lastSuccess ? "stale" : "error";
            root.lastError = `Unable to send low-battery warning: ${message}`;
            console.warn(`Battery warning state: ${root.lastError}`);
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.check()
    }

    Connections {
        target: UPower

        function onOnBatteryChanged(): void {
            root.check();
        }
    }

    Connections {
        target: root.battery

        function onPercentageChanged(): void {
            root.check();
        }

        function onStateChanged(): void {
            root.check();
        }
    }

    IpcHandler {
        target: "battery-warning"

        function check(): string {
            root.check();
            return "ok";
        }

        function status(): string {
            return root.status();
        }

        function ping(): string {
            return "ok";
        }
    }
}
