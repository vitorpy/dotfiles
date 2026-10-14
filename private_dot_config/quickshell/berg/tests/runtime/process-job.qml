import QtQuick
import Quickshell
import "."

Scope {
    id: root
    property int step: 0
    function require(value, message) {
        if (!value) { console.error(message); Qt.exit(1); }
    }
    ProcessJob {
        id: job
        runOnStart: false
        timeoutMs: 1500
        command: ["/usr/bin/printf", "retained"]
        onSucceeded: (code, output, stderr) => {
            if (root.step === 0) {
                root.require(output === "retained", "stdout missing");
                root.step = 1;
                command = ["/definitely/not/a/berg-command"];
                Qt.callLater(refresh);
            } else {
                root.require(root.step === 3 && code === 2, "accepted exit code failed");
                console.log("ProcessJob: success, missing command, stale value, timeout, accepted status passed");
                Qt.quit();
            }
        }
        onFailed: (message, code, output, stderr) => {
            if (root.step === 1) {
                root.require(code === 127 && health === "stale" && job.output === "retained", "failed-start recovery failed");
                root.step = 2;
                command = ["/usr/bin/sleep", "10"];
                timeoutMs = 50;
                Qt.callLater(refresh);
            } else {
                root.require(root.step === 2 && timedOut, "timeout failed");
                root.step = 3;
                timeoutMs = 1500;
                acceptedExitCodes = [0, 2];
                command = ["/usr/bin/sh", "-c", "exit 2"];
                Qt.callLater(refresh);
            }
        }
    }
    Timer { interval: 10000; running: true; onTriggered: { console.error("ProcessJob runtime test hung"); Qt.exit(1); } }
    Component.onCompleted: job.refresh()
}
