pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "MediaModel.js" as MediaModel

Scope {
    id: root

    required property var osd

    property string preferredPlayerKey: ""
    property var playerStartedAt: ({})
    property int playSerial: 0
    property var pendingTrackOsd: null
    property string lastActionRoute: ""

    readonly property var players: Mpris.players ? MediaModel.toArray(Mpris.players.values) : []
    readonly property var pipewireNodes: Pipewire.nodes ? MediaModel.toArray(Pipewire.nodes.values) : []
    readonly property var pipewireLinkGroups: Pipewire.linkGroups
        ? MediaModel.toArray(Pipewire.linkGroups.values) : []
    readonly property var playbackStreams: pipewireNodes.filter(node => root.isPlaybackStreamNode(node))
    readonly property var trackedPipewireObjects: playbackStreams.concat(pipewireLinkGroups)
    readonly property var selectablePlayers: MediaModel.deduplicateAliases(players)
    readonly property var activePlaybackStreams: {
        const streams = [];
        for (const linkGroup of pipewireLinkGroups) {
            if (!linkGroup || linkGroup.state !== PwLinkState.Active)
                continue;
            const stream = root.isPlaybackStreamNode(linkGroup.source)
                ? linkGroup.source
                : (root.isPlaybackStreamNode(linkGroup.target) ? linkGroup.target : null);
            if (stream && streams.indexOf(stream) < 0)
                streams.push(stream);
        }
        return streams;
    }
    readonly property var sourcePlayers: MediaModel.orderedSourcePlayers(selectablePlayers, playerStartedAt)
    readonly property var cyclePlayers: MediaModel.orderedCyclePlayers(selectablePlayers)
    readonly property var activePlayer: MediaModel.selectActivePlayer(
        selectablePlayers,
        activePlaybackStreams,
        playerStartedAt,
        preferredPlayerKey
    )
    readonly property bool visible: MediaModel.hasMeaningfulMetadata(activePlayer)
    readonly property bool playing: Boolean(activePlayer && activePlayer.isPlaying)
    readonly property string title: activePlayer ? String(activePlayer.trackTitle || "") : ""
    readonly property string artist: activePlayer ? String(activePlayer.trackArtist || "") : ""
    readonly property string label: title || artist
    readonly property string barLabel: title && artist ? `${title} · ${artist}` : label
    readonly property string tooltip: {
        if (!activePlayer)
            return "No media player";
        const source = MediaModel.sourceLabel(activePlayer);
        const metadata = MediaModel.osdMessage(activePlayer, source);
        const sourceHint = cyclePlayers.length > 1 ? "\nRight click: next source" : "";
        return `${metadata}\n${source} · ${playing ? "Playing" : "Paused"}`
            + "\nLeft click: play / pause · Middle click: next"
            + "\nWheel: previous / next"
            + sourceHint;
    }

    function isPlaybackStreamNode(node: var): bool {
        return Boolean(node && (
            node.type === PwNodeType.AudioOutStream
            || MediaModel.isPlaybackStream(node)
        ));
    }

    function playerForKey(key: string): var {
        const normalized = String(key || "");
        return selectablePlayers.find(player => MediaModel.playerKey(player) === normalized) || null;
    }

    function syncPlayingOrder(): void {
        const next = {};
        const alive = {};
        let serial = playSerial;

        for (const player of players) {
            const key = MediaModel.playerKey(player);
            if (!key)
                continue;
            alive[key] = true;
            if (!player.isPlaying)
                continue;
            if (playerStartedAt[key] === undefined) {
                serial += 1;
                next[key] = serial;
            } else {
                next[key] = playerStartedAt[key];
            }
        }

        if (preferredPlayerKey && !alive[preferredPlayerKey])
            preferredPlayerKey = "";
        playSerial = serial;
        playerStartedAt = next;
    }

    function actionDetails(action: string, player: var): var {
        if (action === "next")
            return { icon: "media-next", message: "Next track", waitsForTrack: true };
        if (action === "previous")
            return { icon: "media-previous", message: "Previous track", waitsForTrack: true };
        if (action === "play")
            return { icon: "media-play", message: "Play", waitsForTrack: false };
        if (action === "pause")
            return { icon: "media-pause", message: "Pause", waitsForTrack: false };
        if (action === "play-pause") {
            return player && player.isPlaying
                ? { icon: "media-pause", message: "Pause", waitsForTrack: false }
                : { icon: "media-play", message: "Play", waitsForTrack: false };
        }
        return null;
    }

    function invokePlayer(player: var, method: string): bool {
        if (!player || !method)
            return false;
        try {
            if (method === "next")
                player.next();
            else if (method === "previous")
                player.previous();
            else if (method === "play")
                player.play();
            else if (method === "pause")
                player.pause();
            else if (method === "togglePlaying")
                player.togglePlaying();
            else
                return false;
            return true;
        } catch (error) {
            console.warn(`Media state: player disappeared during ${method}: ${error}`);
            return false;
        }
    }

    function fallbackAction(action: string): bool {
        const supported = ["next", "previous", "play", "pause", "play-pause"];
        if (supported.indexOf(action) < 0)
            return false;
        Quickshell.execDetached(["/usr/bin/playerctl", action]);
        lastActionRoute = "playerctl";
        return true;
    }

    function showOsd(details: var, player: var, screenName: string): void {
        if (!details)
            return;
        osd.showMessage(
            details.icon,
            MediaModel.osdMessage(player, details.message),
            screenName
        );
    }

    function scheduleTrackOsd(details: var, player: var, screenName: string,
                              previousSignature: string): void {
        pendingTrackOsd = {
            details: details,
            playerKey: MediaModel.playerKey(player),
            screenName: screenName,
            previousSignature: previousSignature,
            attempts: 0
        };
        trackOsdTimer.restart();
    }

    function flushTrackOsd(force: bool): void {
        const pending = pendingTrackOsd;
        if (!pending)
            return;

        const player = playerForKey(pending.playerKey);
        const changed = player && MediaModel.trackChanged(pending.previousSignature, player);
        if (force || changed || pending.attempts >= 10) {
            pendingTrackOsd = null;
            trackOsdTimer.stop();
            showOsd(pending.details, player, pending.screenName);
            return;
        }

        pending.attempts += 1;
        pendingTrackOsd = pending;
        trackOsdTimer.restart();
    }

    function runAction(action: string, showFeedback: bool, screenName: string,
                       targetKey: string, allowFallback: bool): bool {
        const player = MediaModel.playerForAction(
            selectablePlayers,
            activePlayer,
            action,
            targetKey,
            playerStartedAt
        );
        const details = actionDetails(action, player);
        if (!details)
            return false;

        const previousSignature = MediaModel.trackSignature(player);
        const method = MediaModel.actionMethod(player, action);
        const handled = invokePlayer(player, method);

        if (handled) {
            const key = MediaModel.playerKey(player);
            if (key)
                preferredPlayerKey = key;
            lastActionRoute = "mpris";
            if (showFeedback) {
                if (details.waitsForTrack)
                    scheduleTrackOsd(details, player, screenName, previousSignature);
                else
                    Qt.callLater(() => root.showOsd(details, player, screenName));
            }
            return true;
        }

        if (!allowFallback || !fallbackAction(action)) {
            lastActionRoute = "unhandled";
            return false;
        }
        if (showFeedback)
            Qt.callLater(() => root.showOsd(details, null, screenName));
        return true;
    }

    function selectSource(key: string, screenName: string): bool {
        const player = playerForKey(key);
        if (!player || !MediaModel.hasMetadata(player))
            return false;
        preferredPlayerKey = MediaModel.playerKey(player);
        osd.showMessage("media-source", `Media source: ${MediaModel.sourceLabel(player)}`, screenName);
        return true;
    }

    function setPlayerPlaying(player: var, shouldPlay: bool): bool {
        if (!player)
            return false;
        if (Boolean(player.isPlaying) === shouldPlay)
            return true;
        return invokePlayer(player, MediaModel.actionMethod(player, shouldPlay ? "play" : "pause"));
    }

    function switchSource(delta: int, transferPlayback: bool, showFeedback: bool,
                          screenName: string): bool {
        if (cyclePlayers.length < 2)
            return false;
        const current = activePlayer;
        const next = MediaModel.cycledPlayer(
            selectablePlayers,
            MediaModel.playerKey(current),
            delta
        );
        if (!next)
            return false;

        const currentWasPlaying = Boolean(current && current.isPlaying);
        preferredPlayerKey = MediaModel.playerKey(next);
        if (transferPlayback && currentWasPlaying && next !== current) {
            if (setPlayerPlaying(next, true))
                setPlayerPlaying(current, false);
        }
        if (showFeedback) {
            osd.showMessage(
                "media-source",
                `Media source: ${MediaModel.sourceLabel(next)}`,
                screenName
            );
        }
        return true;
    }

    function status(): string {
        const player = activePlayer;
        return JSON.stringify({
            hasPlayer: Boolean(player),
            hasMedia: visible,
            playing: playing,
            key: MediaModel.playerKey(player),
            identity: player ? String(player.identity || "") : "",
            desktopEntry: player ? String(player.desktopEntry || "") : "",
            title: title,
            artist: artist,
            preferredKey: preferredPlayerKey,
            activePlaybackStreams: activePlaybackStreams.length,
            lastActionRoute: lastActionRoute,
            sources: sourcePlayers.map(source => ({
                key: MediaModel.playerKey(source),
                label: MediaModel.sourceLabel(source),
                title: String(source.trackTitle || ""),
                artist: String(source.trackArtist || ""),
                playing: Boolean(source.isPlaying),
                selected: source === player,
                proxy: MediaModel.isProxyPlayer(source)
            }))
        });
    }

    Component.onCompleted: syncPlayingOrder()
    onPlayersChanged: syncPlayingOrder()

    Instantiator {
        model: root.players

        delegate: Connections {
            required property var modelData
            target: modelData

            function onIsPlayingChanged(): void {
                root.syncPlayingOrder();
            }

            function onPostTrackChanged(): void {
                if (root.pendingTrackOsd
                        && root.pendingTrackOsd.playerKey === MediaModel.playerKey(modelData)) {
                    Qt.callLater(() => root.flushTrackOsd(false));
                }
            }
        }
    }

    Timer {
        id: trackOsdTimer

        interval: 120
        repeat: false
        onTriggered: root.flushTrackOsd(false)
    }

    PwObjectTracker {
        objects: root.trackedPipewireObjects
    }

    IpcHandler {
        target: "media"

        function status(): string {
            return root.status();
        }

        function playPause(): string {
            return root.runAction("play-pause", true, "", "", true) ? "ok" : "unhandled";
        }

        function next(): string {
            return root.runAction("next", true, "", "", true) ? "ok" : "unhandled";
        }

        function previous(): string {
            return root.runAction("previous", true, "", "", true) ? "ok" : "unhandled";
        }

        function play(): string {
            return root.runAction("play", true, "", "", true) ? "ok" : "unhandled";
        }

        function pause(): string {
            return root.runAction("pause", true, "", "", true) ? "ok" : "unhandled";
        }

        function selectSource(playerKey: string, screenName: string): string {
            return root.selectSource(playerKey, screenName) ? "ok" : "unhandled";
        }

        function sourceNext(screenName: string): string {
            return root.switchSource(1, false, true, screenName) ? "ok" : "unhandled";
        }

        function sourcePrevious(screenName: string): string {
            return root.switchSource(-1, false, true, screenName) ? "ok" : "unhandled";
        }

        function sourceSwitch(screenName: string): string {
            return root.switchSource(1, true, true, screenName) ? "ok" : "unhandled";
        }

        function ping(): string {
            return "ok";
        }
    }
}
