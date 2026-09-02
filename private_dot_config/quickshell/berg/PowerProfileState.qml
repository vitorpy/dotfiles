import QtQuick
import Quickshell.Services.UPower
import "PowerProfileDisplay.js" as PowerProfileDisplay

QtObject {
    id: root

    property string profileHealth: "ready"
    property string profileError: ""
    property string displayHealth: "ready"
    property string displayError: ""
    property var lastSuccess: new Date()
    property int expectedProfile: -1
    property var displayPolicy: null
    property string displayPhase: "idle"
    property string displayStatus: ""
    property bool displayPolicyPending: false

    readonly property string health: {
        if (profileHealth === "error" || displayHealth === "error")
            return "error";
        if (profileHealth === "stale" || displayHealth === "stale")
            return "stale";
        if (profileHealth === "loading" || displayHealth === "loading")
            return "loading";
        return "ready";
    }
    readonly property string lastError: [profileError, displayError]
        .filter(message => message.length > 0)
        .join("\n")
    readonly property string label: PowerProfile.toString(PowerProfiles.profile)
    readonly property var availableProfiles: PowerProfiles.hasPerformanceProfile
        ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
        : [PowerProfile.PowerSaver, PowerProfile.Balanced]
    readonly property int automaticProfile: UPower.onBattery ? PowerProfile.PowerSaver : PowerProfile.Balanced
    readonly property int automaticRefreshRate: UPower.onBattery ? 48 : 60
    readonly property string tooltip: {
        const available = availableProfiles.map(profile => PowerProfile.toString(profile)).join(" ");
        const source = UPower.onBattery ? "Battery" : "AC";
        const display = displayStatus ? `\nDisplay: ${displayStatus}` : "";
        const base = `Power profile: ${label}\n${source} policy: ${PowerProfile.toString(automaticProfile)} · ${automaticRefreshRate} Hz${display}\nAvailable: ${available}\nClick to cycle until the power source changes`;
        return lastError ? `${base}\n${lastError}` : base;
    }

    function cycle(): string {
        const currentIndex = availableProfiles.indexOf(PowerProfiles.profile);
        const nextIndex = currentIndex >= 0 ? (currentIndex + 1) % availableProfiles.length : 0;
        const nextProfile = availableProfiles[nextIndex];
        const nextLabel = PowerProfile.toString(nextProfile);
        expectedProfile = nextProfile;
        profileHealth = "loading";
        profileError = "";
        PowerProfiles.profile = expectedProfile;
        verifyTimer.restart();
        return nextLabel;
    }

    function applyAutomaticPolicy(): void {
        expectedProfile = automaticProfile;
        profileHealth = "loading";
        profileError = "";
        PowerProfiles.profile = expectedProfile;
        verifyTimer.restart();

        applyDisplayPolicy();
    }

    function applyDisplayPolicy(): void {
        if (displayQuery.running || displayAction.running) {
            displayPolicyPending = true;
            return;
        }

        displayPolicyPending = false;
        displayHealth = "loading";
        displayError = "";
        displayPhase = "discover";
        displayQuery.refresh();
    }

    function failDisplay(message: string): void {
        displayHealth = lastSuccess ? "stale" : "error";
        displayError = message;
        displayPhase = "idle";
        console.warn(`Power profile state: ${message}`);
        runPendingDisplayPolicy();
    }

    function acceptDisplay(refreshRate: real, fallback: bool): void {
        displayHealth = "ready";
        displayError = "";
        displayStatus = `${displayPolicy.width}x${displayPolicy.height} · ${refreshRate} Hz${fallback ? " (fallback)" : ""}`;
        displayPhase = "idle";
        lastSuccess = new Date();
        runPendingDisplayPolicy();
    }

    function runPendingDisplayPolicy(): void {
        if (!displayPolicyPending)
            return;
        Qt.callLater(applyDisplayPolicy);
    }

    function startDisplayAction(mode: string, fallback: bool): void {
        displayPhase = fallback ? "fallbackAction" : "targetAction";
        displayAction.command = [
            "/usr/bin/hyprctl",
            "eval",
            PowerProfileDisplay.monitorExpression(displayPolicy, mode)
        ];
        displayAction.refresh();
    }

    function consumeDisplayQuery(output: string): void {
        try {
            if (displayPhase === "discover") {
                displayPolicy = PowerProfileDisplay.policy(output, automaticRefreshRate);
                if (!displayPolicy.applicable) {
                    displayHealth = "ready";
                    displayError = "";
                    displayStatus = "not applicable";
                    displayPhase = "idle";
                    lastSuccess = new Date();
                    runPendingDisplayPolicy();
                    return;
                }
                startDisplayAction(displayPolicy.targetMode, false);
                return;
            }

            if (displayPhase === "verifyTarget") {
                if (PowerProfileDisplay.verifies(output, displayPolicy, displayPolicy.targetRefreshRate)) {
                    acceptDisplay(displayPolicy.targetRefreshRate, false);
                    return;
                }
                startFallback();
                return;
            }

            if (displayPhase === "verifyFallback") {
                if (PowerProfileDisplay.verifies(output, displayPolicy, displayPolicy.fallbackRefreshRate)) {
                    acceptDisplay(displayPolicy.fallbackRefreshRate, true);
                    return;
                }
                failDisplay("Display fallback mode was not applied");
            }
        } catch (error) {
            failDisplay(`Unable to interpret Hyprland monitors: ${error}`);
        }
    }

    function startFallback(): void {
        if (!displayPolicy || displayPolicy.fallbackMode === displayPolicy.targetMode) {
            failDisplay("Requested native display mode was not applied");
            return;
        }
        startDisplayAction(displayPolicy.fallbackMode, true);
    }

    readonly property Timer verifyTimer: Timer {
        id: verifyTimer

        interval: 2000
        repeat: false
        onTriggered: {
            if (root.expectedProfile < 0)
                return;
            if (PowerProfiles.profile === root.expectedProfile) {
                root.profileHealth = "ready";
                root.profileError = "";
                root.lastSuccess = new Date();
            } else {
                root.profileHealth = root.lastSuccess ? "stale" : "error";
                root.profileError = "Power profile change was not applied";
                console.warn(`Power profile state: ${root.profileError}`);
            }
            root.expectedProfile = -1;
        }
    }

    readonly property Timer policyTimer: Timer {
        interval: 250
        repeat: false
        onTriggered: root.applyAutomaticPolicy()
    }

    readonly property ProcessJob displayQuery: ProcessJob {
        command: ["/usr/bin/hyprctl", "-j", "monitors"]
        runOnStart: false
        timeoutMs: 5000
        onSucceeded: (exitCode, output, errorOutput) => root.consumeDisplayQuery(output)
        onFailed: (message, exitCode, output, errorOutput) => root.failDisplay(`Unable to query Hyprland monitors: ${message}`)
    }

    readonly property ProcessJob displayAction: ProcessJob {
        runOnStart: false
        timeoutMs: 5000
        onSucceeded: {
            root.displayPhase = root.displayPhase === "fallbackAction" ? "verifyFallback" : "verifyTarget";
            root.displayQuery.refresh();
        }
        onFailed: (message, exitCode, output, errorOutput) => {
            if (root.displayPhase === "targetAction") {
                root.startFallback();
                return;
            }
            root.failDisplay(`Display refresh-rate change failed: ${message}`);
        }
    }

    readonly property Connections profileChanges: Connections {
        target: PowerProfiles

        function onProfileChanged(): void {
            if (root.expectedProfile < 0 || PowerProfiles.profile === root.expectedProfile) {
                root.profileHealth = "ready";
                root.profileError = "";
                root.lastSuccess = new Date();
                root.expectedProfile = -1;
                verifyTimer.stop();
            }
        }
    }

    readonly property Connections powerSourceChanges: Connections {
        target: UPower

        function onOnBatteryChanged(): void {
            root.policyTimer.restart();
        }
    }

    Component.onCompleted: policyTimer.restart()
}
