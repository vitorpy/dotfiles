//@ pragma ShellId berg
//@ pragma AppId org.vitorpy.berg
//@ pragma NativeTextRendering

import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    readonly property bool previewMode: Quickshell.env("BERG_BAR_PREVIEW") === "1"

    BarState {
        id: sharedState
    }

    NotificationToasts {
        notificationState: sharedState.notifications
    }

    IpcHandler {
        target: "shell"

        function reload(): void {
            Quickshell.reload(true);
        }

        function refreshClock(): void {
            sharedState.refreshClock();
        }

        function openClockPanel(screenName: string): void {
            sharedState.notifications.closeCenter();
            sharedState.clock.openPanel(screenName);
        }

        function closeClockPanel(): void {
            sharedState.clock.closePanel();
        }
    }

    Variants {
        model: Quickshell.screens

        Bar {
            barState: sharedState
            previewMode: root.previewMode
        }
    }
}
