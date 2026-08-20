import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Scope {
    id: root

    readonly property var audioSink: Pipewire.defaultAudioSink
    readonly property var audioSource: Pipewire.defaultAudioSource
    readonly property bool headphonesActive: audioRouteState.headphonesActive

    readonly property alias clock: clockState
    readonly property alias brightness: brightnessState
    readonly property alias keyboard: keyboardState
    readonly property alias notifications: notificationState
    readonly property alias updates: updatesState
    readonly property alias reboot: kernelState
    readonly property alias powerProfile: powerProfileState
    readonly property alias systemStats: stats
    readonly property alias pwCenter: pwCenterController

    function refreshClock(): void {
        clockState.refresh();
    }

    function toggleAudioMute(node: var): void {
        if (node && node.audio)
            node.audio.muted = !node.audio.muted;
    }

    function changeAudioVolume(node: var, delta: real): void {
        if (node && node.audio)
            node.audio.volume = Math.max(0, Math.min(1.5, node.audio.volume + delta));
    }

    function changeBrightness(argument: string): void {
        brightnessState.change(argument);
    }

    function toggleKeyboard(): void {
        keyboardState.toggle();
    }

    function toggleDnd(): void {
        notificationState.toggleDnd();
    }

    function toggleNotificationCenter(screenName: string): void {
        clockState.closePanel();
        notificationState.toggleCenter(screenName);
    }

    function toggleClockPanel(screenName: string): void {
        notificationState.closeCenter();
        clockState.togglePanel(screenName);
    }

    function cyclePowerProfile(): void {
        powerProfileState.cycle();
    }

    function togglePwCenter(): void {
        pwCenterController.toggle();
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

    ClockState {
        id: clockState
    }

    BrightnessState {
        id: brightnessState
    }

    KeyboardState {
        id: keyboardState
    }

    NotificationState {
        id: notificationState
    }

    PackageUpdatesState {
        id: updatesState
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

    PwCenterController {
        id: pwCenterController
    }
}
