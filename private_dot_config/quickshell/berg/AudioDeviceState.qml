import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "AudioDeviceModel.js" as AudioDeviceModel

Scope {
    id: root

    required property var popouts
    required property var osd

    readonly property bool panelOpen: popouts.isOpen("audio", "")
    readonly property bool switching: routeJob.running
    readonly property var trackedNodes: sinkDevices.concat(sourceDevices).map(device => device.node)

    property var sinkDevices: []
    property var sourceDevices: []
    property string pendingKind: ""
    property string pendingLabel: ""
    property string pendingSinkName: ""
    property bool pendingSinkAnnounced: false
    property string pendingScreenName: ""
    property string lastError: ""
    property string observedSinkName: ""
    property bool sinkObservationInitialized: false

    function scheduleRefresh(): void {
        settleTimer.stop();
        sinkDevices = [];
        sourceDevices = [];
        if (panelOpen)
            settleTimer.restart();
    }

    function refreshSnapshots(): void {
        if (!panelOpen)
            return;

        sinkDevices = AudioDeviceModel.snapshot(
            Pipewire.nodes.values,
            "sink",
            Pipewire.defaultAudioSink
        );
        sourceDevices = AudioDeviceModel.snapshot(
            Pipewire.nodes.values,
            "source",
            Pipewire.defaultAudioSource
        );
    }

    function devicesFor(kind: string): var {
        if (kind === "sink" && sinkDevices.length > 0)
            return sinkDevices;
        if (kind === "source" && sourceDevices.length > 0)
            return sourceDevices;
        return AudioDeviceModel.snapshot(
            Pipewire.nodes.values,
            kind,
            kind === "sink" ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource
        );
    }

    function selectNode(kind: string, node: var, screenName: string): bool {
        if ((kind !== "sink" && kind !== "source") || !node || !node.name
                || !Number.isFinite(Number(node.id)) || routeJob.running) {
            return false;
        }

        pendingKind = kind;
        pendingLabel = AudioDeviceModel.labelFor(node, kind);
        pendingSinkName = kind === "sink" ? String(node.name) : "";
        pendingSinkAnnounced = false;
        pendingScreenName = screenName;
        lastError = "";

        if (kind === "sink")
            Pipewire.preferredDefaultAudioSink = node;
        else
            Pipewire.preferredDefaultAudioSource = node;

        routeJob.command = [
            `${Quickshell.env("HOME")}/.config/quickshell/berg/scripts/set-audio-route.sh`,
            kind,
            String(node.id),
            String(node.name)
        ];
        routeJob.refresh();
        return true;
    }

    function observeDefaultSink(): void {
        const transition = AudioDeviceModel.defaultSinkTransition(
            observedSinkName,
            sinkObservationInitialized,
            Pipewire.defaultAudioSink
        );
        observedSinkName = transition.name;
        sinkObservationInitialized = transition.initialized;

        if (!transition.shouldAnnounce)
            return;

        const pendingSinkMatched = pendingKind === "sink"
            && transition.name === pendingSinkName;
        const requestedScreenName = pendingSinkMatched ? pendingScreenName : "";
        if (pendingSinkMatched)
            pendingSinkAnnounced = true;

        osd.showMessage("volume", `Audio output: ${transition.label}`, requestedScreenName);
    }

    function clearPending(): void {
        pendingKind = "";
        pendingLabel = "";
        pendingSinkName = "";
        pendingSinkAnnounced = false;
        pendingScreenName = "";
    }

    function selectNamed(kind: string, nodeName: string, screenName: string): bool {
        const normalizedName = String(nodeName || "");
        const devices = devicesFor(kind);
        for (let index = 0; index < devices.length; ++index) {
            if (devices[index].name === normalizedName)
                return selectNode(kind, devices[index].node, screenName);
        }
        return false;
    }

    function openPanel(screenName: string): bool {
        return popouts.openPanel("audio", screenName);
    }

    function closePanel(): void {
        popouts.closePanel("audio");
    }

    function togglePanel(screenName: string): bool {
        return popouts.togglePanel("audio", screenName);
    }

    function status(): string {
        return JSON.stringify({
            opened: panelOpen,
            screenName: popouts.screenName,
            switching: switching,
            defaultSink: Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.name : "",
            defaultSource: Pipewire.defaultAudioSource ? Pipewire.defaultAudioSource.name : "",
            observedSink: observedSinkName,
            sinks: sinkDevices.map(device => ({
                name: device.name,
                label: device.label,
                active: device.active,
                jabra: device.jabra
            })),
            sources: sourceDevices.map(device => ({
                name: device.name,
                label: device.label,
                active: device.active,
                jabra: device.jabra
            })),
            lastError: lastError
        });
    }

    Timer {
        id: settleTimer

        interval: 90
        repeat: false
        onTriggered: root.refreshSnapshots()
    }

    PwObjectTracker {
        objects: root.panelOpen ? root.trackedNodes : []
    }

    ProcessJob {
        id: routeJob

        runOnStart: false
        timeoutMs: 8000

        onSucceeded: {
            const kindLabel = root.pendingKind === "source" ? "Audio input" : "Audio output";
            if (root.pendingKind === "source" || !root.pendingSinkAnnounced) {
                root.osd.showMessage(
                    root.pendingKind === "source" ? "microphone" : "volume",
                    `${kindLabel}: ${root.pendingLabel}`,
                    root.pendingScreenName
                );
            }
            root.lastError = "";
            root.scheduleRefresh();
            root.clearPending();
        }

        onFailed: message => {
            root.lastError = message;
            root.osd.showMessage("warning", "Audio route change failed", root.pendingScreenName);
            root.scheduleRefresh();
            root.clearPending();
        }
    }

    IpcHandler {
        target: "audio"

        function openPanel(screenName: string): string {
            return root.openPanel(screenName) ? "ok" : "unavailable";
        }

        function closePanel(): string {
            root.closePanel();
            return "ok";
        }

        function selectOutput(nodeName: string, screenName: string): string {
            return root.selectNamed("sink", nodeName, screenName) ? "ok" : "unavailable";
        }

        function selectInput(nodeName: string, screenName: string): string {
            return root.selectNamed("source", nodeName, screenName) ? "ok" : "unavailable";
        }

        function status(): string {
            return root.status();
        }

        function ping(): string {
            return "ok";
        }
    }

    Connections {
        target: Pipewire.nodes

        function onValuesChanged(): void {
            root.scheduleRefresh();
        }
    }

    Connections {
        target: Pipewire

        function onDefaultAudioSinkChanged(): void {
            root.scheduleRefresh();
            root.observeDefaultSink();
        }

        function onDefaultAudioSourceChanged(): void {
            root.scheduleRefresh();
        }
    }

    Component.onCompleted: observeDefaultSink()
    onPanelOpenChanged: scheduleRefresh()
}
