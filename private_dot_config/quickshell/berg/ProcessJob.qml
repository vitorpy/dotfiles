import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property var command: []
    property var environment: ({})
    property var acceptedExitCodes: [0]
    property int intervalMs: 0
    property int timeoutMs: 5000
    property bool enabled: true
    property bool runOnStart: true

    property string output: ""
    property string errorOutput: ""
    property string health: "loading"
    property string lastError: ""
    property var lastSuccess: null
    property int lastExitCode: -1
    property bool refreshPending: false
    property bool timedOut: false

    readonly property alias running: process.running

    signal succeeded(int exitCode, string output, string errorOutput)
    signal failed(string message, int exitCode, string output, string errorOutput)

    function refresh(): void {
        if (!enabled || command.length === 0)
            return;

        if (process.running) {
            refreshPending = true;
            return;
        }

        timedOut = false;
        process.command = command;
        process.environment = environment;
        process.running = true;
    }

    readonly property Process process: Process {
        id: process

        stdout: StdioCollector {
            id: stdoutCollector
        }
        stderr: StdioCollector {
            id: stderrCollector
        }

        onStarted: {
            if (root.timeoutMs > 0)
                timeoutTimer.restart();
        }

        onExited: (exitCode, exitStatus) => {
            timeoutTimer.stop();
            killTimer.stop();

            const stdoutText = stdoutCollector.text.trim();
            const stderrText = stderrCollector.text.trim();
            const accepted = root.acceptedExitCodes.indexOf(exitCode) >= 0 && !root.timedOut;

            root.lastExitCode = exitCode;
            root.errorOutput = stderrText;

            if (accepted) {
                root.output = stdoutText;
                root.lastError = "";
                root.lastSuccess = new Date();
                root.health = "ready";
                root.succeeded(exitCode, stdoutText, stderrText);
            } else {
                const message = root.timedOut
                    ? `Command timed out after ${root.timeoutMs} ms`
                    : (stderrText || `Command exited with status ${exitCode}`);
                root.lastError = message;
                root.health = root.lastSuccess ? "stale" : "error";
                root.failed(message, exitCode, stdoutText, stderrText);
            }

            if (root.refreshPending) {
                root.refreshPending = false;
                Qt.callLater(root.refresh);
            }
        }
    }

    readonly property Timer timeoutTimer: Timer {
        id: timeoutTimer

        interval: Math.max(1, root.timeoutMs)
        repeat: false
        onTriggered: {
            if (!process.running)
                return;
            root.timedOut = true;
            process.signal(15);
            killTimer.restart();
        }
    }

    readonly property Timer killTimer: Timer {
        id: killTimer

        interval: 1000
        repeat: false
        onTriggered: {
            if (process.running)
                process.signal(9);
        }
    }

    readonly property Timer pollTimer: Timer {
        interval: Math.max(1, root.intervalMs)
        running: root.enabled && root.intervalMs > 0
        repeat: true
        triggeredOnStart: root.runOnStart
        onTriggered: root.refresh()
    }

    Component.onCompleted: {
        if (enabled && runOnStart && intervalMs === 0)
            refresh();
    }
}
