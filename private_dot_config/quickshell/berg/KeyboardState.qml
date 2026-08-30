import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "KeyboardLayoutPersistence.js" as KeyboardLayoutPersistence

QtObject {
    id: root

    readonly property string statePath: Quickshell.statePath("keyboard-layout.json")

    property string keyboardName: ""
    property string layout: "?"
    property bool hasValue: false
    property string health: "loading"
    property string lastError: ""
    property var lastSuccess: null
    property bool stateLoaded: false
    property string pendingRestoreLayout: ""
    property bool restoring: false
    property string actionKind: ""

    function normalizedLayout(value: string): string {
        return KeyboardLayoutPersistence.normalizeLayout(value);
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
        if (pendingRestoreLayout && layout === pendingRestoreLayout) {
            pendingRestoreLayout = "";
            restoring = false;
        }
        hasValue = layout !== "?";
        health = hasValue ? "ready" : "error";
        lastError = hasValue ? "" : "Hyprland did not report an active keyboard layout";
        if (hasValue) {
            lastSuccess = new Date();
            persistLayout(layout);
        }
    }

    function restoreState(): void {
        try {
            const decoded = KeyboardLayoutPersistence.decodeState(stateFile.text());
            pendingRestoreLayout = decoded.layout;
        } catch (error) {
            console.warn(`Keyboard state: unable to restore persisted layout: ${error}`);
            pendingRestoreLayout = "";
        }
        stateLoaded = true;
        query.refresh();
    }

    function persistLayout(value: string): void {
        if (!stateLoaded || KeyboardLayoutPersistence.layoutId(value) < 0)
            return;
        try {
            stateFile.setText(KeyboardLayoutPersistence.encodeState(value));
        } catch (error) {
            console.warn(`Keyboard state: unable to persist layout: ${error}`);
        }
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

            const activeLayout = normalizedLayout(keyboard.active_keymap || "");
            if (pendingRestoreLayout && activeLayout !== pendingRestoreLayout) {
                keyboardName = keyboard.name || "";
                const targetId = KeyboardLayoutPersistence.layoutId(pendingRestoreLayout);
                if (targetId < 0) {
                    fail(`Persisted keyboard layout is unsupported: ${pendingRestoreLayout}`);
                    pendingRestoreLayout = "";
                    return;
                }
                if (!restoring) {
                    restoring = true;
                    actionKind = "restore";
                    action.command = ["/usr/bin/hyprctl", "switchxkblayout", "all", String(targetId)];
                    action.refresh();
                }
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
        pendingRestoreLayout = "";
        restoring = false;
        actionKind = "toggle";
        action.command = ["/usr/bin/hyprctl", "switchxkblayout", keyboardName, "next"];
        action.refresh();
    }

    readonly property ProcessJob query: ProcessJob {
        command: ["/usr/bin/hyprctl", "devices", "-j"]
        runOnStart: false
        intervalMs: 60000
        timeoutMs: 3000
        onSucceeded: (exitCode, output, errorOutput) => root.consumeDevices(output)
        onFailed: (message, exitCode, output, errorOutput) => root.fail(message)
    }

    readonly property ProcessJob action: ProcessJob {
        runOnStart: false
        timeoutMs: 3000
        onSucceeded: {
            root.restoring = false;
            root.query.refresh();
        }
        onFailed: (message, exitCode, output, errorOutput) => {
            const operation = root.actionKind === "restore" ? "restore" : "switch";
            root.restoring = false;
            if (root.actionKind === "restore")
                root.pendingRestoreLayout = "";
            root.fail(`Unable to ${operation} layout: ${message}`);
        }
    }

    readonly property Connections hyprlandEvents: Connections {
        target: Hyprland

        function onRawEvent(event): void {
            if (event.name !== "activelayout")
                return;
            const fields = event.parse(2);
            if (fields.length < 2 || !root.keyboardName) {
                root.query.refresh();
                return;
            }
            if (fields[0] === root.keyboardName)
                root.accept(fields[0], fields[1]);
        }
    }

    readonly property FileView stateFile: FileView {
        path: root.statePath
        preload: false
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                console.warn(`Keyboard state: unable to load ${path}: ${FileViewError.toString(error)}`);
        }
        onSaveFailed: error => {
            console.warn(`Keyboard state: unable to save ${path}: ${FileViewError.toString(error)}`);
        }
    }

    Component.onCompleted: restoreState()
}
