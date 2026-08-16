import QtQuick
import Quickshell
import Quickshell.Hyprland

QtObject {
    id: root

    property bool launchPending: false
    property bool closePending: false
    property string health: "ready"
    property string lastError: ""
    property var lastSuccess: new Date()

    function matchingToplevels(): var {
        return Hyprland.toplevels.values.filter(toplevel => {
            const ipc = toplevel.lastIpcObject || {};
            const ipcClass = ipc["class"] || "";
            const appId = toplevel.wayland ? (toplevel.wayland.appId || "") : "";
            return ipcClass === "hyprpwcenter" || appId === "hyprpwcenter";
        });
    }

    function closeToplevel(toplevel: var): void {
        if (toplevel.wayland) {
            toplevel.wayland.close();
            return;
        }

        if (Hyprland.usingLua)
            Hyprland.dispatch(`hl.dsp.window.close({ window = "address:${toplevel.address}" })`);
        else
            Hyprland.dispatch(`closewindow address:${toplevel.address}`);
    }

    function toggle(): void {
        if (launchPending || closePending)
            return;

        const matches = matchingToplevels();
        if (matches.length > 0) {
            closePending = true;
            for (const toplevel of matches)
                closeToplevel(toplevel);
            closeTimeout.restart();
            return;
        }

        launchPending = true;
        health = "ready";
        lastError = "";
        Quickshell.execDetached(["/usr/bin/uwsm", "app", "--", "/usr/bin/hyprpwcenter"]);
        launchTimeout.restart();
    }

    function observeModel(): void {
        const matches = matchingToplevels();
        if (launchPending && matches.length > 0) {
            launchPending = false;
            launchTimeout.stop();
            health = "ready";
            lastError = "";
            lastSuccess = new Date();
        }
        if (closePending && matches.length === 0) {
            closePending = false;
            closeTimeout.stop();
            health = "ready";
            lastError = "";
            lastSuccess = new Date();
        }
    }

    readonly property Connections modelChanges: Connections {
        target: Hyprland.toplevels

        function onValuesChanged(): void {
            root.observeModel();
        }
    }

    readonly property Timer launchTimeout: Timer {
        id: launchTimeout

        interval: 5000
        repeat: false
        onTriggered: {
            root.launchPending = false;
            if (root.matchingToplevels().length === 0) {
                root.health = "error";
                root.lastError = "HyprPWCenter did not open within five seconds";
                console.warn(`HyprPWCenter state: ${root.lastError}`);
            }
        }
    }

    readonly property Timer closeTimeout: Timer {
        id: closeTimeout

        interval: 2000
        repeat: false
        onTriggered: {
            root.closePending = false;
            if (root.matchingToplevels().length > 0) {
                root.health = "error";
                root.lastError = "HyprPWCenter did not close within two seconds";
                console.warn(`HyprPWCenter state: ${root.lastError}`);
            }
        }
    }
}
