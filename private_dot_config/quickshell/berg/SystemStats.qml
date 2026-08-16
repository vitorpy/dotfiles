import QtQuick
import Quickshell.Io

QtObject {
    id: root

    readonly property string cpuPath: "/proc/stat"
    readonly property string temperaturePath: "/sys/class/thermal/thermal_zone0/temp"

    property int cpuUsage: 0
    property int temperatureC: 0
    property bool cpuHasValue: false
    property bool temperatureHasValue: false
    property string cpuError: ""
    property string temperatureError: ""
    property string health: "loading"
    property string lastError: ""
    property var lastSuccess: null
    property real previousCpuTotal: -1
    property real previousCpuIdle: -1

    function updateHealth(): void {
        const errors = [cpuError, temperatureError].filter(message => message.length > 0);
        lastError = errors.join("\n");
        if (errors.length === 0 && cpuHasValue && temperatureHasValue) {
            health = "ready";
            lastSuccess = new Date();
        } else if (cpuHasValue || temperatureHasValue) {
            health = "stale";
        } else {
            health = "error";
        }
    }

    function consumeCpu(text: string): void {
        const firstLine = text.split("\n")[0].trim();
        const fields = firstLine.split(/\s+/);
        if (fields.length < 6 || fields[0] !== "cpu") {
            cpuError = "/proc/stat returned an invalid CPU record";
            updateHealth();
            return;
        }

        let total = 0;
        for (let index = 1; index < fields.length; ++index) {
            const value = Number(fields[index]);
            if (!Number.isFinite(value)) {
                cpuError = "/proc/stat contained a non-numeric CPU counter";
                updateHealth();
                return;
            }
            total += value;
        }

        const idle = Number(fields[4]) + Number(fields[5]);
        let usage = 0;
        if (previousCpuTotal >= 0 && total > previousCpuTotal) {
            const totalDelta = total - previousCpuTotal;
            const idleDelta = idle - previousCpuIdle;
            usage = 100 * (totalDelta - idleDelta) / totalDelta;
        } else if (total > 0) {
            usage = 100 * (total - idle) / total;
        }

        previousCpuTotal = total;
        previousCpuIdle = idle;
        cpuUsage = Math.max(0, Math.min(100, Math.round(usage)));
        cpuHasValue = true;
        cpuError = "";
        updateHealth();
    }

    function consumeTemperature(text: string): void {
        const millidegrees = Number(text.trim());
        if (Number.isFinite(millidegrees)) {
            temperatureC = Math.round(millidegrees / 1000);
            temperatureHasValue = true;
            temperatureError = "";
        } else {
            temperatureError = "Thermal sensor returned an invalid temperature";
        }
        updateHealth();
    }

    readonly property FileView cpuFile: FileView {
        path: root.cpuPath
        printErrors: false
        onLoaded: root.consumeCpu(text())
        onLoadFailed: error => {
            root.cpuError = `Unable to read CPU statistics: ${FileViewError.toString(error)}`;
            root.updateHealth();
        }
    }

    readonly property FileView temperatureFile: FileView {
        path: root.temperaturePath
        printErrors: false
        onLoaded: root.consumeTemperature(text())
        onLoadFailed: error => {
            root.temperatureError = `Unable to read temperature: ${FileViewError.toString(error)}`;
            root.updateHealth();
        }
    }

    readonly property Timer refreshTimer: Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.cpuFile.reload();
            root.temperatureFile.reload();
        }
    }
}
