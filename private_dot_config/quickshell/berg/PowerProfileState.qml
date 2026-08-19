import QtQuick
import Quickshell.Services.UPower

QtObject {
    id: root

    property string profileHealth: "ready"
    property string profileError: ""
    property string displayHealth: "ready"
    property string displayError: ""
    property var lastSuccess: new Date()
    property int expectedProfile: -1

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
        const base = `Power profile: ${label}\n${source} policy: ${PowerProfile.toString(automaticProfile)} · ${automaticRefreshRate} Hz\nAvailable: ${available}\nClick to cycle until the power source changes`;
        return lastError ? `${base}\n${lastError}` : base;
    }

    function cycle(): void {
        const currentIndex = availableProfiles.indexOf(PowerProfiles.profile);
        const nextIndex = currentIndex >= 0 ? (currentIndex + 1) % availableProfiles.length : 0;
        expectedProfile = availableProfiles[nextIndex];
        profileHealth = "loading";
        profileError = "";
        PowerProfiles.profile = expectedProfile;
        verifyTimer.restart();
    }

    function applyAutomaticPolicy(): void {
        expectedProfile = automaticProfile;
        profileHealth = "loading";
        profileError = "";
        displayHealth = "loading";
        displayError = "";

        PowerProfiles.profile = expectedProfile;
        verifyTimer.restart();

        displayAction.command = [
            "/usr/bin/hyprctl",
            "eval",
            `hl.monitor({ output = "eDP-1", mode = "2256x1504@${automaticRefreshRate}", position = "auto", scale = 1 })`
        ];
        displayAction.refresh();
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

    readonly property ProcessJob displayAction: ProcessJob {
        runOnStart: false
        timeoutMs: 5000
        onSucceeded: {
            root.displayHealth = "ready";
            root.displayError = "";
            root.lastSuccess = new Date();
        }
        onFailed: (message, exitCode, output, errorOutput) => {
            root.displayHealth = root.lastSuccess ? "stale" : "error";
            root.displayError = `Display refresh-rate change failed: ${message}`;
            console.warn(`Power profile state: ${root.displayError}`);
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
            policyTimer.restart();
        }
    }

    Component.onCompleted: policyTimer.restart()
}
