import QtQuick
import "PackageUpdates.js" as PackageUpdates

QtObject {
    id: root

    property int officialCount: 0
    property int aurCount: 0
    property bool officialHasValue: false
    property bool aurHasValue: false
    property bool officialDone: false
    property bool aurDone: false
    property string officialError: ""
    property string aurError: ""
    property string health: "loading"
    property string lastError: ""
    property var lastSuccess: null
    property bool refreshPending: false

    readonly property int total: officialCount + aurCount
    readonly property bool visible: total > 0 || health === "stale" || health === "error"
    readonly property string tooltip: {
        const summary = total > 0
            ? (aurCount > 0 ? `${officialCount} official, ${aurCount} AUR updates` : `${officialCount} updates available`)
            : "System up to date";
        return lastError ? `${summary}\n${lastError}` : summary;
    }

    function refresh(): void {
        if (PackageUpdates.refreshIsBusy(official.running, aur.running)) {
            refreshPending = true;
            return;
        }

        officialDone = false;
        aurDone = false;
        officialError = "";
        aurError = "";
        official.refresh();
        aur.refresh();
    }

    function finishSource(source: string, success: bool, output: string, message: string): void {
        if (source === "official") {
            officialDone = true;
            if (success) {
                officialCount = PackageUpdates.lineCount(output);
                officialHasValue = true;
            } else {
                officialError = `Official update check failed: ${message}`;
            }
        } else {
            aurDone = true;
            if (success) {
                aurCount = PackageUpdates.lineCount(output);
                aurHasValue = true;
            } else {
                aurError = `AUR update check failed: ${message}`;
            }
        }

        finalizeIfReady();
    }

    function finalizeIfReady(): void {
        if (!officialDone || !aurDone)
            return;

        const errors = [officialError, aurError].filter(message => message.length > 0);
        lastError = errors.join("\n");
        if (errors.length === 0) {
            health = "ready";
            lastSuccess = new Date();
        } else {
            health = officialHasValue || aurHasValue ? "stale" : "error";
            console.warn(`Package update state: ${lastError}`);
        }

        if (refreshPending) {
            refreshPending = false;
            Qt.callLater(refresh);
        }
    }

    readonly property ProcessJob official: ProcessJob {
        command: ["/usr/bin/checkupdates"]
        acceptedExitCodes: [0, 2]
        runOnStart: false
        timeoutMs: 60000
        onSucceeded: (exitCode, output, errorOutput) => root.finishSource("official", true, output, "")
        onFailed: (message, exitCode, output, errorOutput) => root.finishSource("official", false, output, message)
    }

    readonly property ProcessJob aur: ProcessJob {
        command: ["/usr/bin/yay", "-Qua"]
        runOnStart: false
        timeoutMs: 60000
        onSucceeded: (exitCode, output, errorOutput) => root.finishSource("aur", true, output, "")
        onFailed: (message, exitCode, output, errorOutput) => {
            if (exitCode === 1 && !output.trim() && !errorOutput.trim())
                root.finishSource("aur", true, "", "");
            else
                root.finishSource("aur", false, output, message);
        }
    }

    readonly property Timer refreshTimer: Timer {
        interval: PackageUpdates.periodicRefreshIntervalMs()
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
