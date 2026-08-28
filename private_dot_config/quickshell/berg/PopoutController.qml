import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "PopoutModel.js" as PopoutModel

Scope {
    id: root

    readonly property var panelIds: ["audio", "clock", "notifications", "power"]
    property string activePanel: ""
    property string screenName: ""

    readonly property bool anyOpen: activePanel.length > 0

    function panelKnown(panelId: string): bool {
        return panelIds.indexOf(PopoutModel.normalizePanelId(panelId)) >= 0;
    }

    function focusedScreenName(): string {
        if (Hyprland.focusedMonitor && Hyprland.focusedMonitor.name)
            return Hyprland.focusedMonitor.name;
        return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "";
    }

    function screenExists(candidate: string): bool {
        for (let index = 0; index < Quickshell.screens.length; ++index) {
            if (Quickshell.screens[index].name === candidate)
                return true;
        }
        return false;
    }

    function resolveScreenName(requestedScreenName: string): string {
        if (requestedScreenName && screenExists(requestedScreenName))
            return requestedScreenName;
        return focusedScreenName();
    }

    function isOpen(panelId: string, candidateScreenName: string): bool {
        if (activePanel !== PopoutModel.normalizePanelId(panelId))
            return false;
        return !candidateScreenName || screenName === candidateScreenName;
    }

    function openPanel(panelId: string, requestedScreenName: string): bool {
        if (!panelKnown(panelId))
            return false;

        const state = PopoutModel.openState(
            panelId,
            resolveScreenName(requestedScreenName),
            focusedScreenName()
        );
        activePanel = state.activePanel;
        screenName = state.screenName;
        return true;
    }

    function closePanel(panelId: string): bool {
        const normalizedId = PopoutModel.normalizePanelId(panelId);
        if (normalizedId && activePanel !== normalizedId)
            return false;
        if (!activePanel)
            return false;

        activePanel = "";
        screenName = "";
        return true;
    }

    function togglePanel(panelId: string, requestedScreenName: string): bool {
        if (!panelKnown(panelId))
            return false;

        const state = PopoutModel.toggleState(
            activePanel,
            screenName,
            panelId,
            resolveScreenName(requestedScreenName),
            focusedScreenName()
        );
        activePanel = state.activePanel;
        screenName = state.screenName;
        return activePanel === PopoutModel.normalizePanelId(panelId);
    }

    function rehomeMissingScreen(): void {
        if (!anyOpen || screenExists(screenName))
            return;

        const fallback = focusedScreenName();
        if (fallback)
            screenName = fallback;
        else
            closePanel("");
    }

    function status(): string {
        return JSON.stringify({
            activePanel: activePanel,
            screenName: screenName
        });
    }

    IpcHandler {
        target: "panels"

        function openPanel(panelId: string, screenName: string): string {
            return root.openPanel(panelId, screenName) ? "ok" : "unknown";
        }

        function closePanel(panelId: string): string {
            root.closePanel(panelId);
            return "ok";
        }

        function togglePanel(panelId: string, screenName: string): string {
            if (!root.panelKnown(panelId))
                return "unknown";
            root.togglePanel(panelId, screenName);
            return "ok";
        }

        function status(): string {
            return root.status();
        }

        function ping(): string {
            return "ok";
        }
    }

    Connections {
        target: Quickshell

        function onScreensChanged(): void {
            root.rehomeMissingScreen();
        }
    }
}
