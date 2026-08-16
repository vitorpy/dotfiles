import QtQuick
import Quickshell.Hyprland

QtObject {
    id: root

    property string keyboardName: ""
    property string layout: "?"
    property bool hasValue: false
    property string health: "loading"
    property string lastError: ""
    property var lastSuccess: null

    function normalizedLayout(value: string): string {
        if (!value)
            return "?";
        if (/Polish|Polski|^pl/i.test(value))
            return "PL";
        if (/intl|English|^US/i.test(value))
            return "EN";
        return value;
    }

    function fail(message: string): void {
        lastError = message;
        health = hasValue ? "stale" : "error";
        console.warn(`Keyboard state: ${message}`);
    }

    function accept(name: string, activeLayout: string): void {
        if (name)
            keyboardName = name;
        layout = normalizedLayout(activeLayout);
        hasValue = layout !== "?";
        health = hasValue ? "ready" : "error";
        lastError = hasValue ? "" : "Hyprland did not report an active keyboard layout";
        if (hasValue)
            lastSuccess = new Date();
    }

    function consumeDevices(text: string): void {
        try {
            const payload = JSON.parse(text);
            const keyboards = Array.isArray(payload.keyboards) ? payload.keyboards : [];
            const keyboard = keyboards.find(candidate => candidate.main === true);
            if (!keyboard) {
                fail("Hyprland did not report a main keyboard");
                return;
            }
            accept(keyboard.name || "", keyboard.active_keymap || "");
        } catch (error) {
            fail(`Unable to parse Hyprland devices: ${error}`);
        }
    }

    function toggle(): void {
        if (!keyboardName) {
            query.refresh();
            return;
        }
        action.command = ["/usr/bin/hyprctl", "switchxkblayout", keyboardName, "next"];
        action.refresh();
    }

    readonly property ProcessJob query: ProcessJob {
        command: ["/usr/bin/hyprctl", "devices", "-j"]
        intervalMs: 60000
        timeoutMs: 3000
        onSucceeded: (exitCode, output, errorOutput) => root.consumeDevices(output)
        onFailed: (message, exitCode, output, errorOutput) => root.fail(message)
    }

    readonly property ProcessJob action: ProcessJob {
        runOnStart: false
        timeoutMs: 3000
        onSucceeded: root.query.refresh()
        onFailed: (message, exitCode, output, errorOutput) => root.fail(`Unable to switch layout: ${message}`)
    }

    readonly property Connections hyprlandEvents: Connections {
        target: Hyprland

        function onRawEvent(event): void {
            if (event.name !== "activelayout")
                return;
            const fields = event.parse(2);
            if (fields.length >= 2)
                root.accept(root.keyboardName, fields[1]);
            else
                root.query.refresh();
        }
    }
}
