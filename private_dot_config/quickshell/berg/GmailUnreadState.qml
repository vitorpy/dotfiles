import QtQuick
import Quickshell
import "GmailUnread.js" as GmailUnread

QtObject {
    id: root

    readonly property string home: Quickshell.env("HOME")

    property bool configured: false
    property string countField: "threadsUnread"
    property int total: 0
    property var accounts: []
    property string health: "loading"
    property string lastError: ""
    property var lastSuccess: null

    readonly property bool visible: (configured && GmailUnread.hasUnread(total)) || health === "stale" || health === "error"
    readonly property string badgeText: GmailUnread.badgeText(total)
    readonly property string tooltip: {
        const base = GmailUnread.tooltip({
            configured: configured,
            countField: countField,
            total: total,
            accounts: accounts
        });
        return lastError ? `${base}\n${lastError}` : base;
    }

    function refresh(): void {
        poller.refresh();
    }

    function consume(text: string): void {
        try {
            const result = GmailUnread.parsePayload(text);
            configured = result.configured;
            countField = result.countField;
            total = result.total;
            accounts = result.accounts;
            lastError = "";
            health = configured ? "ready" : "disabled";
            if (configured)
                lastSuccess = new Date();
        } catch (error) {
            markFailed(`Unread result is malformed: ${error}`);
        }
    }

    function markFailed(message: string): void {
        lastError = message;
        health = lastSuccess ? "stale" : "error";
        console.warn(`Gmail unread state: ${message}`);
    }

    readonly property ProcessJob poller: ProcessJob {
        command: [`${root.home}/.config/quickshell/berg/scripts/gmail-unread.py`, "status"]
        intervalMs: GmailUnread.periodicRefreshIntervalMs()
        timeoutMs: 30000
        onSucceeded: (exitCode, output, errorOutput) => root.consume(output)
        onFailed: (message, exitCode, output, errorOutput) => root.markFailed(message)
    }
}
