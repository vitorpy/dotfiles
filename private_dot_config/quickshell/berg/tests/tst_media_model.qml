import QtQuick
import QtTest
import "../MediaModel.js" as MediaModel

TestCase {
    name: "MediaModel"

    function player(key, overrides) {
        return Object.assign({
            dbusName: `org.mpris.MediaPlayer2.${key}`,
            desktopEntry: key,
            identity: key,
            trackTitle: "",
            trackArtist: "",
            trackAlbum: "",
            trackArtUrl: "",
            uniqueId: 0,
            isPlaying: false,
            canTogglePlaying: true,
            canPlay: true,
            canPause: true,
            canGoNext: true,
            canGoPrevious: true
        }, overrides || {});
    }

    function stream(applicationName) {
        return {
            ready: true,
            isStream: true,
            isSink: true,
            type: "Stream/Output/Audio",
            properties: {
                "media.class": "Stream/Output/Audio",
                "application.name": applicationName
            }
        };
    }

    function test_proxyAndMetadataClassification() {
        verify(MediaModel.isProxyPlayer(player("playerctld")));
        verify(!MediaModel.isProxyPlayer(player("spotify")));
        verify(MediaModel.hasMetadata(player("spotify")));
        verify(!MediaModel.hasMeaningfulMetadata(player("spotify")));
        verify(MediaModel.hasMeaningfulMetadata(player("spotify", { trackTitle: "Song" })));
    }

    function test_playbackStreamCorrelationUsesNormalizedApplicationNames() {
        const chromium = player("chromium.instance42", {
            dbusName: "org.mpris.MediaPlayer2.chromium.instance42",
            desktopEntry: "chromium"
        });
        verify(MediaModel.isPlaybackStream(stream("PipeWire ALSA [Chromium]")));
        verify(MediaModel.playerHasPlaybackStream(chromium, [stream("Chromium")]));
        verify(!MediaModel.playerHasPlaybackStream(chromium, [stream("Spotify")]));
    }

    function test_oldestPlayingRealPlayerWinsOverProxyAndStalePlayers() {
        const proxy = player("playerctld", { isPlaying: true, trackTitle: "Proxy" });
        const newer = player("vlc", { isPlaying: true, trackTitle: "Newer" });
        const oldest = player("spotify", { isPlaying: true, trackTitle: "Oldest" });
        const stale = player("firefox", { trackTitle: "Paused" });
        const selected = MediaModel.selectActivePlayer(
            [proxy, newer, stale, oldest],
            [stream("VLC"), stream("Spotify")],
            {
                "org.mpris.MediaPlayer2.playerctld": 1,
                "org.mpris.MediaPlayer2.spotify": 2,
                "org.mpris.MediaPlayer2.vlc": 3
            },
            ""
        );
        compare(MediaModel.playerKey(selected), "org.mpris.MediaPlayer2.spotify");
    }

    function test_activePipewireStreamBeatsStaleTrackMetadata() {
        const stale = player("alpha", { trackTitle: "Old track", canTogglePlaying: false });
        const streaming = player("beta", { identity: "Beta", canTogglePlaying: false });
        const selected = MediaModel.selectActivePlayer(
            [stale, streaming],
            [stream("Beta")],
            {},
            ""
        );
        compare(MediaModel.playerKey(selected), "org.mpris.MediaPlayer2.beta");
    }

    function test_explicitSourceSelectionOverridesAutomaticOrdering() {
        const playing = player("spotify", { isPlaying: true, trackTitle: "Song" });
        const paused = player("vlc", { trackTitle: "Film" });
        const selected = MediaModel.selectActivePlayer(
            [playing, paused],
            [],
            { "org.mpris.MediaPlayer2.spotify": 1 },
            "org.mpris.MediaPlayer2.vlc"
        );
        compare(MediaModel.playerKey(selected), "org.mpris.MediaPlayer2.vlc");
    }

    function test_sourceOrderingAndCyclingAreDeterministic() {
        const zulu = player("zulu", { trackTitle: "Zulu" });
        const alpha = player("alpha", { trackTitle: "Alpha" });
        const proxy = player("playerctld", { trackTitle: "Proxy" });
        const ordered = MediaModel.orderedCyclePlayers([zulu, proxy, alpha]);
        compare(MediaModel.playerKey(ordered[0]), "org.mpris.MediaPlayer2.alpha");
        compare(MediaModel.playerKey(ordered[2]), "org.mpris.MediaPlayer2.playerctld");
        compare(
            MediaModel.playerKey(MediaModel.cycledPlayer(
                [zulu, proxy, alpha],
                "org.mpris.MediaPlayer2.alpha",
                1
            )),
            "org.mpris.MediaPlayer2.zulu"
        );
    }

    function test_sameProcessStyleAliasesAreDeduplicated() {
        const canonical = player("vlc", {
            dbusName: "org.mpris.MediaPlayer2.vlc",
            trackTitle: "Film",
            trackArtist: "Director",
            isPlaying: true
        });
        const instance = player("vlc", {
            dbusName: "org.mpris.MediaPlayer2.vlc.instance4242",
            trackTitle: "Film",
            trackArtist: "Director",
            isPlaying: true
        });
        const distinct = player("vlc", {
            dbusName: "org.mpris.MediaPlayer2.vlc.instance5252",
            trackTitle: "Film",
            trackArtist: "Director",
            isPlaying: true
        });
        const deduplicated = MediaModel.deduplicateAliases([canonical, instance, distinct]);
        compare(deduplicated.length, 2);
        compare(MediaModel.playerKey(deduplicated[0]), "org.mpris.MediaPlayer2.vlc.instance4242");
    }

    function test_actionPlanningChecksCapabilitiesAndPlaybackState() {
        const playing = player("spotify", { isPlaying: true });
        const paused = player("vlc", { isPlaying: false });
        compare(MediaModel.actionMethod(playing, "play-pause"), "pause");
        compare(MediaModel.actionMethod(paused, "play-pause"), "play");
        compare(MediaModel.actionMethod(player("limited", { canGoNext: false }), "next"), "");
        compare(MediaModel.actionMethod(null, "previous"), "");
    }

    function test_actionSelectionHandlesMissingAndDisappearingTargets() {
        const active = player("spotify", { trackTitle: "Song" });
        compare(MediaModel.playerForAction([], null, "next", "missing", {}), null);
        compare(
            MediaModel.playerKey(MediaModel.playerForAction(
                [active],
                active,
                "next",
                "org.mpris.MediaPlayer2.disappeared",
                {}
            )),
            "org.mpris.MediaPlayer2.spotify"
        );
    }

    function test_trackSignatureAndMetadataOsd() {
        const track = player("spotify", {
            uniqueId: 7,
            trackTitle: "Song",
            trackArtist: "Artist"
        });
        const signature = MediaModel.trackSignature(track);
        verify(!MediaModel.trackChanged(signature, track));
        verify(MediaModel.trackChanged(signature, Object.assign({}, track, { uniqueId: 8 })));
        compare(MediaModel.osdMessage(track, "Next track"), "Song — Artist");
        compare(MediaModel.osdMessage(null, "Next track"), "Next track");
    }

    function test_acceptsQmlListLikeValues() {
        const spotify = player("spotify", { trackTitle: "Song" });
        const listLike = { 0: spotify, length: 1 };
        compare(MediaModel.toArray(listLike).length, 1);
        compare(MediaModel.orderedSourcePlayers(listLike, {}).length, 1);
    }
}
