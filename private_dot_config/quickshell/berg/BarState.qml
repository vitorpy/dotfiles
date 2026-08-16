import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Scope {
    id: root

    readonly property var audioSink: Pipewire.defaultAudioSink
    readonly property var audioSource: Pipewire.defaultAudioSource

    readonly property var brightnessData: parseJson(brightnessPoll.output, {
        "percent": 0
    })
    readonly property var clockData: parseJson(clockPoll.output, {
        "text": "",
        "tooltip": ""
    })
    readonly property var keyboardData: ({
        "text": keyboardPoll.output || "?"
    })
    readonly property var dndData: parseJson(dndPoll.output, {
        "text": "",
        "tooltip": ""
    })
    readonly property var updatesData: parseJson(updatesPoll.output, {
        "text": "",
        "tooltip": "",
        "class": "up-to-date"
    })
    readonly property var rebootData: parseJson(rebootPoll.output, {
        "text": "",
        "tooltip": "",
        "class": ""
    })
    readonly property var profileData: parseJson(profilePoll.output, {
        "text": "",
        "tooltip": "",
        "available": []
    })
    readonly property alias systemStats: stats

    function script(name: string): string {
        return Quickshell.shellPath(`scripts/${name}`);
    }

    function parseJson(text: string, fallback: var): var {
        if (!text)
            return fallback;

        try {
            return JSON.parse(text);
        } catch (error) {
            console.warn(`Berg bar received invalid JSON: ${error}`);
            return fallback;
        }
    }

    function refreshClock(): void {
        clockPoll.refresh();
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
        brightnessAction.exec(["/usr/bin/brightnessctl", "set", argument]);
    }

    function toggleKeyboard(): void {
        keyboardAction.exec([script("kbtoggle.sh")]);
    }

    function toggleDnd(): void {
        dndAction.exec([script("dnd-toggle.sh")]);
    }

    function dismissNotifications(): void {
        Quickshell.execDetached(["/usr/bin/makoctl", "dismiss", "-a"]);
    }

    function cyclePowerProfile(): void {
        profileAction.exec([script("power-profile.sh"), "cycle"]);
    }

    function togglePwCenter(): void {
        Quickshell.execDetached([script("hyprpwcenter-toggle.sh")]);
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

    SystemStats {
        id: stats
    }

    CommandPoll {
        id: brightnessPoll
        command: [root.script("brightness-status.sh")]
        intervalMs: 2000
    }

    CommandPoll {
        id: clockPoll
        command: [root.script("smart-clock.sh")]
        intervalMs: 30000
    }

    CommandPoll {
        id: keyboardPoll
        command: [root.script("kblayout.sh")]
        intervalMs: 1000
    }

    CommandPoll {
        id: dndPoll
        command: [root.script("dnd-status.sh")]
        intervalMs: 2000
    }

    CommandPoll {
        id: updatesPoll
        command: [root.script("pacman-updates.sh")]
        intervalMs: 300000
    }

    CommandPoll {
        id: rebootPoll
        command: [root.script("reboot-required.sh")]
        intervalMs: 300000
    }

    CommandPoll {
        id: profilePoll
        command: [root.script("power-profile.sh"), "status"]
        intervalMs: 5000
    }

    Process {
        id: brightnessAction
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: brightnessRefreshDelay.restart()
    }

    Timer {
        id: brightnessRefreshDelay
        interval: 150
        repeat: false
        onTriggered: brightnessPoll.refresh()
    }

    Process {
        id: keyboardAction
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: keyboardPoll.refresh()
    }

    Process {
        id: dndAction
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: dndPoll.refresh()
    }

    Process {
        id: profileAction
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: profilePoll.refresh()
    }
}
