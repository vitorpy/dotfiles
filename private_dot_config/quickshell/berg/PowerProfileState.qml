import QtQuick
import Quickshell.Services.UPower

QtObject {
    id: root

    property string health: "ready"
    property string lastError: ""
    property var lastSuccess: new Date()
    property int expectedProfile: -1

    readonly property string label: PowerProfile.toString(PowerProfiles.profile)
    readonly property var availableProfiles: PowerProfiles.hasPerformanceProfile
        ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
        : [PowerProfile.PowerSaver, PowerProfile.Balanced]
    readonly property string tooltip: {
        const available = availableProfiles.map(profile => PowerProfile.toString(profile)).join(" ");
        const base = `Power profile: ${label}\nAvailable: ${available}\nClick to cycle`;
        return lastError ? `${base}\n${lastError}` : base;
    }

    function cycle(): void {
        const currentIndex = availableProfiles.indexOf(PowerProfiles.profile);
        const nextIndex = currentIndex >= 0 ? (currentIndex + 1) % availableProfiles.length : 0;
        expectedProfile = availableProfiles[nextIndex];
        lastError = "";
        PowerProfiles.profile = expectedProfile;
        verifyTimer.restart();
    }

    readonly property Timer verifyTimer: Timer {
        id: verifyTimer

        interval: 2000
        repeat: false
        onTriggered: {
            if (root.expectedProfile < 0)
                return;
            if (PowerProfiles.profile === root.expectedProfile) {
                root.health = "ready";
                root.lastError = "";
                root.lastSuccess = new Date();
            } else {
                root.health = root.lastSuccess ? "stale" : "error";
                root.lastError = "Power profile change was not applied";
                console.warn(`Power profile state: ${root.lastError}`);
            }
            root.expectedProfile = -1;
        }
    }

    readonly property Connections profileChanges: Connections {
        target: PowerProfiles

        function onProfileChanged(): void {
            if (root.expectedProfile < 0 || PowerProfiles.profile === root.expectedProfile) {
                root.health = "ready";
                root.lastError = "";
                root.lastSuccess = new Date();
                root.expectedProfile = -1;
                verifyTimer.stop();
            }
        }
    }
}
