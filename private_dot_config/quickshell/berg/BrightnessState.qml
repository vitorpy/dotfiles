import QtQuick

QtObject {
    id: root

    signal changeApplied(int percent)
    signal changeFailed(string message)

    property int percent: 0
    property bool hasValue: false
    property string health: "loading"
    property string lastError: ""
    property var lastSuccess: null
    property bool reportNextConsume: false

    function fail(message: string): void {
        lastError = message;
        health = hasValue ? "stale" : "error";
        console.warn(`Brightness state: ${message}`);
    }

    function consume(text: string): void {
        const fields = text.split(",");
        if (fields.length < 5) {
            fail("brightnessctl returned an incomplete record");
            return;
        }

        const match = fields[3].trim().match(/^([0-9]+)%$/);
        if (!match) {
            fail("brightnessctl returned an invalid percentage");
            return;
        }

        percent = Math.max(0, Math.min(100, Number(match[1])));
        hasValue = true;
        health = "ready";
        lastError = "";
        lastSuccess = new Date();
        if (reportNextConsume) {
            reportNextConsume = false;
            changeApplied(percent);
        }
    }

    function change(argument: string): void {
        action.command = ["/usr/bin/brightnessctl", "set", argument];
        action.refresh();
    }

    readonly property ProcessJob query: ProcessJob {
        command: ["/usr/bin/brightnessctl", "-m"]
        intervalMs: 2000
        timeoutMs: 2000
        onSucceeded: (exitCode, output, errorOutput) => root.consume(output)
        onFailed: (message, exitCode, output, errorOutput) => {
            if (root.reportNextConsume) {
                root.reportNextConsume = false;
                root.changeFailed(message);
            }
            root.fail(message);
        }
    }

    readonly property ProcessJob action: ProcessJob {
        runOnStart: false
        timeoutMs: 3000
        onSucceeded: {
            root.lastError = "";
            root.reportNextConsume = true;
            refreshDelay.restart();
        }
        onFailed: (message, exitCode, output, errorOutput) => {
            root.reportNextConsume = false;
            root.changeFailed(message);
            root.fail(`Unable to change brightness: ${message}`);
        }
    }

    readonly property Timer refreshDelay: Timer {
        id: refreshDelay

        interval: 150
        repeat: false
        onTriggered: root.query.refresh()
    }
}
