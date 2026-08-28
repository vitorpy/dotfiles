//@ pragma UseQApplication
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

        function ping(): string {
            return "ok";
        }

        function reload(): void {
            Quickshell.reload(true);
        }

        function refreshClock(): void {
            sharedState.refreshClock();
        }

        function refreshUpdates(): void {
            sharedState.refreshUpdates();
        }

        function updatesStatus(): string {
            return sharedState.updatesStatus();
        }

        function openClockPanel(screenName: string): void {
            sharedState.clock.openPanel(screenName);
        }

        function closeClockPanel(): void {
            sharedState.clock.closePanel();
        }
    }

    IpcHandler {
        target: "actions"

        function volumeUp(): string {
            return sharedState.changeAudioVolume(sharedState.audioSink, 0.05, false, "")
                ? "ok" : "unavailable";
        }

        function volumeDown(): string {
            return sharedState.changeAudioVolume(sharedState.audioSink, -0.05, false, "")
                ? "ok" : "unavailable";
        }

        function toggleOutputMute(): string {
            return sharedState.toggleAudioMute(sharedState.audioSink, false, "")
                ? "ok" : "unavailable";
        }

        function toggleInputMute(): string {
            return sharedState.toggleAudioMute(sharedState.audioSource, true, "")
                ? "ok" : "unavailable";
        }

        function brightnessUp(): string {
            sharedState.changeBrightness("+10%", "");
            return "ok";
        }

        function brightnessDown(): string {
            sharedState.changeBrightness("10%-", "");
            return "ok";
        }

        function brightnessMax(): string {
            sharedState.changeBrightness("100%", "");
            return "ok";
        }

        function cyclePowerProfile(): string {
            sharedState.cyclePowerProfile("");
            return "ok";
        }

        function mediaNext(): string {
            return sharedState.runMediaAction("next", "") ? "ok" : "unknown";
        }

        function mediaPrevious(): string {
            return sharedState.runMediaAction("previous", "") ? "ok" : "unknown";
        }

        function mediaPlayPause(): string {
            return sharedState.runMediaAction("play-pause", "") ? "ok" : "unknown";
        }

        function status(): string {
            return JSON.stringify({
                outputAvailable: Boolean(sharedState.audioSink && sharedState.audioSink.audio),
                inputAvailable: Boolean(sharedState.audioSource && sharedState.audioSource.audio),
                brightnessAvailable: sharedState.brightness.hasValue,
                mediaAvailable: Boolean(sharedState.media.activePlayer)
            });
        }

        function ping(): string {
            return "ok";
        }
    }

    Variants {
        model: Quickshell.screens

        Bar {
            barState: sharedState
            previewMode: root.previewMode
        }
    }

    Variants {
        model: Quickshell.screens

        Osd {
            osdState: sharedState.osd
        }
    }
}
