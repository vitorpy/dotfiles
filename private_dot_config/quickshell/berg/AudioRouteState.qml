import QtQuick
import Quickshell.Bluetooth
import Quickshell.Io
import "AudioRoute.js" as AudioRoute

QtObject {
    id: root

    property var sink: null
    property bool headphonesActive: false
    property string bluetoothAddress: ""
    property string health: "loading"
    property string lastError: ""
    property var lastSuccess: null
    property bool subscriptionStarted: false

    readonly property var bluetoothDevice: {
        if (!bluetoothAddress)
            return null;

        return Bluetooth.devices.values.find(device =>
            device && AudioRoute.normalizeBluetoothAddress(device.address) === bluetoothAddress
        ) || null;
    }
    readonly property bool batteryAvailable: Boolean(
        bluetoothDevice && bluetoothDevice.connected && bluetoothDevice.batteryAvailable
    )
    readonly property int batteryPercent: {
        if (!batteryAvailable || !Number.isFinite(bluetoothDevice.battery))
            return 0;

        return Math.round(Math.max(0, Math.min(1, bluetoothDevice.battery)) * 100);
    }

    function refreshSoon(): void {
        refreshTimer.restart();
    }

    function markFailure(message: string): void {
        health = lastSuccess ? "stale" : "error";
        lastError = message;
        console.warn(`Audio route state: ${message}`);
    }

    function updateFromPactl(output: string): void {
        try {
            const sinkName = sink ? sink.name : "";
            const activeSink = AudioRoute.activeSinkInfo(output, sinkName);
            headphonesActive = activeSink.headphonesActive;
            bluetoothAddress = activeSink.bluetoothAddress;
            health = "ready";
            lastError = "";
            lastSuccess = new Date();
        } catch (error) {
            markFailure(`Could not parse pactl sink data: ${error}`);
        }
    }

    onSinkChanged: refreshSoon()

    readonly property Timer refreshTimer: Timer {
        id: refreshTimer

        interval: 100
        repeat: false
        onTriggered: routeQuery.refresh()
    }

    readonly property ProcessJob routeQuery: ProcessJob {
        id: routeQuery

        command: ["/usr/bin/pactl", "--format=json", "list", "sinks"]
        runOnStart: false
        timeoutMs: 5000
        onSucceeded: (exitCode, output, errorOutput) => root.updateFromPactl(output)
        onFailed: (message, exitCode, output, errorOutput) => {
            root.markFailure(`Could not inspect the active audio route: ${message}`);
        }
    }

    readonly property Process subscription: Process {
        id: subscription

        command: ["/usr/bin/pactl", "subscribe"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data.trim().length > 0)
                    root.refreshSoon();
            }
        }
        stderr: StdioCollector {
            id: subscriptionError
        }
        onRunningChanged: {
            if (!running && root.subscriptionStarted) {
                const detail = subscriptionError.text.trim();
                root.markFailure(detail || "pactl subscribe stopped");
                reconnectTimer.restart();
            }
        }
    }

    readonly property Timer reconnectTimer: Timer {
        id: reconnectTimer

        interval: 2000
        repeat: false
        onTriggered: {
            if (!subscription.running)
                subscription.running = true;
            root.refreshSoon();
        }
    }

    Component.onCompleted: {
        subscriptionStarted = true;
        subscription.running = true;
        refreshSoon();
    }
}
