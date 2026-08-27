import QtQuick
import Quickshell
import Quickshell.Io
import "OsdModel.js" as OsdModel

Scope {
    id: root

    required property var panelController

    property bool opened: false
    property string screenName: ""
    property string iconKey: "warning"
    property string message: ""
    property real value: 0
    property real maximum: 100
    property bool hasProgress: false
    property int duration: 1200

    function applyState(state: var, requestedScreenName: string): void {
        iconKey = state.iconKey;
        message = state.message;
        value = state.value;
        maximum = state.maximum;
        hasProgress = state.hasProgress;
        duration = state.duration;
        screenName = panelController.resolveScreenName(requestedScreenName);
        opened = screenName.length > 0;

        if (opened && duration > 0)
            hideTimer.restart();
        else
            hideTimer.stop();
    }

    function showProgress(icon: string, rawValue: real, rawMaximum: real,
                          requestedScreenName: string, progressText: string): void {
        applyState(
            OsdModel.stateForShow(icon, progressText, rawValue, rawMaximum, 1200),
            requestedScreenName
        );
    }

    function showMessage(icon: string, text: string, requestedScreenName: string): void {
        applyState(
            OsdModel.stateForShow(icon, text, undefined, 100, 1200),
            requestedScreenName
        );
    }

    function showPayload(payloadJson: string): string {
        try {
            const state = OsdModel.stateForPayload(payloadJson);
            applyState(state, state.screenName);
            return "ok";
        } catch (error) {
            console.warn(`OSD state: invalid payload: ${error}`);
            return "invalid";
        }
    }

    function close(): void {
        hideTimer.stop();
        opened = false;
        screenName = "";
    }

    function status(): string {
        return JSON.stringify({
            opened: opened,
            screenName: screenName,
            icon: iconKey,
            message: message,
            value: value,
            max: maximum,
            hasProgress: hasProgress
        });
    }

    Timer {
        id: hideTimer

        interval: Math.max(1, root.duration)
        repeat: false
        onTriggered: root.close()
    }

    IpcHandler {
        target: "osd"

        function show(payloadJson: string): string {
            return root.showPayload(payloadJson);
        }

        function close(): string {
            root.close();
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
            if (!root.opened || root.panelController.screenExists(root.screenName))
                return;
            root.screenName = root.panelController.resolveScreenName("");
            if (!root.screenName)
                root.close();
        }
    }
}
