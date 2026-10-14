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
    property bool awaitingCompletion: false

    readonly property bool running: process.running || awaitingCompletion

    signal succeeded(int exitCode, string output, string errorOutput)
    signal failed(string message, int exitCode, string output, string errorOutput)

    function refresh(): void {
        if (!enabled || command.length === 0)
            return;

        if (running) {
            refreshPending = true;
            return;
        }

        timedOut = false;
        awaitingCompletion = true;
        // env turns a missing child executable into a normal exit (127).
        // Quickshell 0.3.1 does not expose QProcess::errorOccurred to QML.
        process.command = ["/usr/bin/env", "--"].concat(command);
        process.environment = environment;
        if (timeoutMs > 0)
            timeoutTimer.restart();
        process.running = true;
    }

    function finish(exitCode: int, stdoutText: string, stderrText: string): void {
        if (!awaitingCompletion)
            return;
        awaitingCompletion = false;
        timeoutTimer.stop();
        killTimer.stop();
        const accepted = acceptedExitCodes.indexOf(exitCode) >= 0 && !timedOut;
        lastExitCode = exitCode;
        errorOutput = stderrText;
        if (accepted) {
            output = stdoutText;
            lastError = "";
            lastSuccess = new Date();
            health = "ready";
            succeeded(exitCode, stdoutText, stderrText);
        } else {
            const message = timedOut ? `Command timed out after ${timeoutMs} ms`
                : (stderrText || `Command exited with status ${exitCode}`);
            lastError = message;
            health = lastSuccess ? "stale" : "error";
            failed(message, exitCode, stdoutText, stderrText);
        }
        if (refreshPending) {
            refreshPending = false;
            Qt.callLater(refresh);
        }
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
            root.finish(exitCode, stdoutCollector.text.trim(), stderrCollector.text.trim());
        }
    }

    readonly property Timer timeoutTimer: Timer {
        id: timeoutTimer

        interval: Math.max(1, root.timeoutMs)
        repeat: false
        onTriggered: {
            if (!process.running) {
                root.finish(-1, "", `Command failed to start: ${root.command[0]}`);
                return;
            }
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
