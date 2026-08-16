import QtQuick

QtObject {
    id: root

    property bool enabled: false
    property bool hasValue: false
    property string health: "loading"
    property string lastError: ""
    property var lastSuccess: null

    readonly property string tooltip: health === "ready"
        ? `Do Not Disturb: ${enabled ? "ON" : "OFF"}`
        : `Do Not Disturb: ${hasValue ? (enabled ? "ON" : "OFF") : "unavailable"}\n${lastError}`

    function fail(message: string): void {
        lastError = message;
        health = hasValue ? "stale" : "error";
        console.warn(`DND state: ${message}`);
    }

    function consume(text: string): void {
        const modes = text.split(/\r?\n/).map(mode => mode.trim()).filter(mode => mode.length > 0);
        enabled = modes.indexOf("do-not-disturb") >= 0;
        hasValue = true;
        health = "ready";
        lastError = "";
        lastSuccess = new Date();
    }

    function toggle(): void {
        if (!hasValue) {
            query.refresh();
            return;
        }
        action.command = ["/usr/bin/makoctl", "mode", "-s", enabled ? "default" : "do-not-disturb"];
        action.refresh();
    }

    readonly property ProcessJob query: ProcessJob {
        command: ["/usr/bin/makoctl", "mode"]
        intervalMs: 2000
        timeoutMs: 2000
        onSucceeded: (exitCode, output, errorOutput) => root.consume(output)
        onFailed: (message, exitCode, output, errorOutput) => root.fail(message)
    }

    readonly property ProcessJob action: ProcessJob {
        runOnStart: false
        timeoutMs: 3000
        onSucceeded: root.query.refresh()
        onFailed: (message, exitCode, output, errorOutput) => root.fail(`Unable to change DND mode: ${message}`)
    }
}
