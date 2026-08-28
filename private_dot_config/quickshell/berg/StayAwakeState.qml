import QtQuick
import Quickshell
import Quickshell.Io
import "StayAwakeModel.js" as StayAwakeModel

Scope {
    id: root

    required property var osd

    readonly property string statePath: Quickshell.statePath("stay-awake-session.json")
    readonly property string sessionToken: {
        const xdgSession = String(Quickshell.env("XDG_SESSION_ID") || "");
        const hyprlandSession = String(Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "");
        const token = [xdgSession, hyprlandSession].filter(value => value.length > 0).join(":");
        return token || `process:${Quickshell.processId}`;
    }

    property bool enabled: false
    property bool stateLoaded: false

    function restoreState(): void {
        let shouldSeed = false;
        try {
            const decoded = StayAwakeModel.decodeState(stateFile.text(), sessionToken);
            enabled = decoded.enabled;
            shouldSeed = decoded.shouldSeed;
        } catch (error) {
            console.warn(`Stay-awake state: unable to restore state: ${error}`);
            enabled = false;
            shouldSeed = true;
        }

        stateLoaded = true;
        if (shouldSeed)
            persistState();
    }

    function persistState(): void {
        if (!stateLoaded)
            return;
        stateFile.setText(StayAwakeModel.encodeState(enabled, sessionToken));
    }

    function applyAction(action: string, screenName: string): bool {
        let nextValue;
        try {
            nextValue = StayAwakeModel.nextEnabled(enabled, action);
        } catch (error) {
            return false;
        }

        enabled = nextValue;
        persistState();
        osd.showMessage(
            "power",
            nextValue ? "Stay awake enabled" : "Stay awake disabled",
            screenName
        );
        return true;
    }

    function enable(screenName: string): bool {
        return applyAction("enable", screenName);
    }

    function disable(screenName: string): bool {
        return applyAction("disable", screenName);
    }

    function toggle(screenName: string): bool {
        return applyAction("toggle", screenName);
    }

    function status(): string {
        return JSON.stringify(StayAwakeModel.status(enabled, stateLoaded));
    }

    FileView {
        id: stateFile

        path: root.statePath
        preload: false
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                console.warn(`Stay-awake state: unable to load ${path}: ${FileViewError.toString(error)}`);
        }
        onSaveFailed: error => {
            console.warn(`Stay-awake state: unable to save ${path}: ${FileViewError.toString(error)}`);
        }
    }

    IpcHandler {
        target: "stay-awake"

        function enable(): string {
            return root.enable("") ? "ok" : "unavailable";
        }

        function disable(): string {
            return root.disable("") ? "ok" : "unavailable";
        }

        function toggle(): string {
            return root.toggle("") ? "ok" : "unavailable";
        }

        function status(): string {
            return root.status();
        }

        function ping(): string {
            return "ok";
        }
    }

    Component.onCompleted: restoreState()
}
