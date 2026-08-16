import QtQuick
import Quickshell.Io

QtObject {
    id: root

    readonly property string cpuPath: "/proc/stat"
    readonly property string temperaturePath: "/sys/class/thermal/thermal_zone0/temp"

    property int cpuUsage: 0
    property int temperatureC: 0
    property real previousCpuTotal: -1
    property real previousCpuIdle: -1

    function consumeCpu(text: string): void {
        const firstLine = text.split("\n")[0].trim();
        const fields = firstLine.split(/\s+/);
        if (fields.length < 6 || fields[0] !== "cpu")
            return;

        let total = 0;
        for (let index = 1; index < fields.length; ++index) {
            const value = Number(fields[index]);
            if (!Number.isFinite(value))
                return;
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
    }

    function consumeTemperature(text: string): void {
        const millidegrees = Number(text.trim());
        if (Number.isFinite(millidegrees))
            temperatureC = Math.round(millidegrees / 1000);
    }

    readonly property FileView cpuFile: FileView {
        path: root.cpuPath
        printErrors: false
        onLoaded: root.consumeCpu(text())
    }

    readonly property FileView temperatureFile: FileView {
        path: root.temperaturePath
        printErrors: false
        onLoaded: root.consumeTemperature(text())
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
