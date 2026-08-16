import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property var command: []
    property int intervalMs: 0
    property bool enabled: true
    property string output: ""
    property string errorOutput: ""
    property int lastExitCode: -1
    property bool refreshPending: false

    signal finished(int exitCode, string output, string errorOutput)

    function refresh(): void {
        if (!enabled || command.length === 0)
            return;

        if (process.running) {
            refreshPending = true;
            return;
        }

        process.running = true;
    }

    readonly property Process process: Process {
        id: process

        command: root.command
        stdout: StdioCollector {
            id: stdoutCollector
        }
        stderr: StdioCollector {
            id: stderrCollector
        }

        onExited: (exitCode, exitStatus) => {
            const stdoutText = stdoutCollector.text.trim();
            const stderrText = stderrCollector.text.trim();

            root.lastExitCode = exitCode;
            root.errorOutput = stderrText;
            if (exitCode === 0)
                root.output = stdoutText;

            root.finished(exitCode, stdoutText, stderrText);

            if (root.refreshPending) {
                root.refreshPending = false;
                Qt.callLater(root.refresh);
            }
        }
    }

    readonly property Timer pollTimer: Timer {
        interval: Math.max(1, root.intervalMs)
        running: root.enabled && root.intervalMs > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: {
        if (intervalMs === 0)
            refresh();
    }
}
