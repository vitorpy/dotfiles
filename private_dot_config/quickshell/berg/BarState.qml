import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "PackageUpdates.js" as PackageUpdates

Scope {
    id: root

    readonly property var audioSink: Pipewire.defaultAudioSink
    readonly property var audioSource: Pipewire.defaultAudioSource
    readonly property bool headphonesActive: audioRouteState.headphonesActive
    readonly property bool audioSinkBatteryAvailable: audioRouteState.batteryAvailable
    readonly property int audioSinkBatteryPercent: audioRouteState.batteryPercent

    readonly property alias clock: clockState
    readonly property alias brightness: brightnessState
    readonly property alias keyboard: keyboardState
    readonly property alias notifications: notificationState
    readonly property alias updates: updatesState
    readonly property alias gmailUnread: gmailUnreadState
    readonly property alias reboot: kernelState
    readonly property alias powerProfile: powerProfileState
    readonly property alias systemStats: stats
    readonly property alias audioDevices: audioDeviceState
    readonly property alias stayAwake: stayAwakeState
    readonly property alias media: mediaState
    readonly property alias panels: popoutController
    readonly property alias osd: osdState
    readonly property alias batteryWarning: batteryWarningState

    property string pendingBrightnessScreenName: ""

    function refreshClock(): void {
        clockState.refresh();
    }

    function refreshUpdates(): void {
        updatesState.refresh();
    }

    function launchUpdates(): void {
        Quickshell.execDetached(PackageUpdates.launchCommand(Quickshell.env("HOME")));
    }

    function updatesStatus(): string {
        return JSON.stringify({
            officialCount: updatesState.officialCount,
            aurCount: updatesState.aurCount,
            total: updatesState.total,
            health: updatesState.health,
            running: updatesState.official.running || updatesState.aur.running,
            refreshPending: updatesState.refreshPending
        });
    }

    function refreshGmailUnread(): void {
        gmailUnreadState.refresh();
    }

    function gmailUnreadStatus(): string {
        return JSON.stringify({
            configured: gmailUnreadState.configured,
            countField: gmailUnreadState.countField,
            total: gmailUnreadState.total,
            accounts: gmailUnreadState.accounts,
            health: gmailUnreadState.health,
            running: gmailUnreadState.poller.running
        });
    }

    function audioIconKey(node: var, input: bool): string {
        if (!node || !node.audio)
            return "warning";
        if (input)
            return node.audio.muted ? "microphone-muted" : "microphone";
        if (node.audio.muted)
            return "volume-muted";
        return headphonesActive ? "headphones" : "volume";
    }

    function toggleAudioMute(node: var, input: bool, screenName: string): bool {
        if (!node || !node.audio) {
            osdState.showMessage("warning", input ? "Audio input unavailable" : "Audio output unavailable", screenName);
            return false;
        }

        const nextMuted = !node.audio.muted;
        node.audio.muted = nextMuted;
        osdState.showMessage(
            input ? (nextMuted ? "microphone-muted" : "microphone")
                  : (nextMuted ? "volume-muted" : (headphonesActive ? "headphones" : "volume")),
            input
                ? (nextMuted ? "Microphone muted" : "Microphone on")
                : (nextMuted ? "Audio muted" : "Audio on"),
            screenName
        );
        return true;
    }

    function changeAudioVolume(node: var, delta: real, input: bool, screenName: string): bool {
        if (!node || !node.audio) {
            osdState.showMessage("warning", input ? "Audio input unavailable" : "Audio output unavailable", screenName);
            return false;
        }

        const nextVolume = Math.max(0, Math.min(1.5, node.audio.volume + delta));
        node.audio.volume = nextVolume;
        osdState.showProgress(
            audioIconKey(node, input),
            Math.round(nextVolume * 100),
            150,
            screenName,
            `${Math.round(nextVolume * 100)}%`
        );
        return true;
    }

    function changeBrightness(argument: string, screenName: string): bool {
        pendingBrightnessScreenName = screenName;
        brightnessState.change(argument);
        return true;
    }

    function toggleKeyboard(): void {
        keyboardState.toggle();
    }

    function toggleDnd(): void {
        notificationState.toggleDnd();
    }

    function toggleNotificationCenter(screenName: string): void {
        notificationState.toggleCenter(screenName);
    }

    function toggleClockPanel(screenName: string): void {
        clockState.togglePanel(screenName);
    }

    function togglePowerMenu(screenName: string): void {
        popoutController.togglePanel("power", screenName);
    }

    function toggleAudioPanel(screenName: string): void {
        audioDeviceState.togglePanel(screenName);
    }

    function toggleStayAwake(screenName: string): void {
        stayAwakeState.toggle(screenName);
    }

    function cyclePowerProfile(screenName: string): void {
        const label = powerProfileState.cycle();
        osdState.showMessage("power", `Power profile: ${label}`, screenName);
    }

    function runMediaAction(action: string, screenName: string): bool {
        return mediaState.runAction(action, true, screenName, "", true);
    }

    function cycleMediaSource(delta: int, screenName: string): bool {
        return mediaState.switchSource(delta, false, true, screenName);
    }

    function runSessionAction(action: string): void {
        Quickshell.execDetached([
            `${Quickshell.env("HOME")}/.config/hypr/session-exit.sh`,
            action
        ]);
    }

    PwObjectTracker {
        objects: [root.audioSink, root.audioSource]
    }

    AudioRouteState {
        id: audioRouteState

        sink: root.audioSink
    }

    PopoutController {
        id: popoutController
    }

    OsdState {
        id: osdState

        panelController: popoutController
    }

    AudioDeviceState {
        id: audioDeviceState

        popouts: popoutController
        osd: osdState
    }

    StayAwakeState {
        id: stayAwakeState

        osd: osdState
    }

    MediaState {
        id: mediaState

        osd: osdState
    }

    BatteryWarningState {
        id: batteryWarningState
    }

    ClockState {
        id: clockState

        popouts: popoutController
    }

    BrightnessState {
        id: brightnessState
    }

    KeyboardState {
        id: keyboardState
    }

    NotificationState {
        id: notificationState

        popouts: popoutController
    }

    PackageUpdatesState {
        id: updatesState
    }

    GmailUnreadState {
        id: gmailUnreadState
    }

    KernelState {
        id: kernelState
    }

    PowerProfileState {
        id: powerProfileState
    }

    SystemStats {
        id: stats
    }

    Connections {
        target: brightnessState

        function onChangeApplied(percent: int): void {
            osdState.showProgress(
                "brightness",
                percent,
                100,
                root.pendingBrightnessScreenName,
                ""
            );
            root.pendingBrightnessScreenName = "";
        }

        function onChangeFailed(message: string): void {
            osdState.showMessage(
                "warning",
                "Brightness unavailable",
                root.pendingBrightnessScreenName
            );
            root.pendingBrightnessScreenName = "";
        }
    }
}
