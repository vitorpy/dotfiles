function toArray(values) {
    if (!values)
        return [];
    if (Array.isArray(values))
        return values.slice();

    const result = [];
    const length = Number(values.length) || 0;
    for (let index = 0; index < length; ++index)
        result.push(values[index]);
    return result;
}

function text(value) {
    return value === undefined || value === null ? "" : String(value).trim();
}

function isProxyPlayer(player) {
    const dbusName = text(player && player.dbusName).toLowerCase();
    const desktopEntry = text(player && player.desktopEntry).toLowerCase();
    return dbusName.indexOf("playerctld") >= 0 || desktopEntry === "playerctld";
}

function hasMetadata(player) {
    return Boolean(player && (
        text(player.trackTitle)
        || text(player.trackArtist)
        || text(player.identity)
        || text(player.desktopEntry)
    ));
}

function hasTrackMetadata(player) {
    return Boolean(player && (
        text(player.trackTitle)
        || text(player.trackArtist)
        || text(player.trackAlbum)
        || text(player.trackArtUrl)
    ));
}

function hasMeaningfulMetadata(player) {
    return Boolean(player && (text(player.trackTitle) || text(player.trackArtist)));
}

function playerCanControl(player) {
    return Boolean(player && (
        player.canTogglePlaying
        || player.canPlay
        || player.canPause
        || player.canGoNext
        || player.canGoPrevious
    ));
}

function actionMethod(player, action) {
    if (!player)
        return "";

    if (action === "next")
        return player.canGoNext ? "next" : "";
    if (action === "previous")
        return player.canGoPrevious ? "previous" : "";
    if (action === "play") {
        if (player.isPlaying)
            return "";
        if (player.canPlay)
            return "play";
        return player.canTogglePlaying ? "togglePlaying" : "";
    }
    if (action === "pause") {
        if (!player.isPlaying)
            return "";
        if (player.canPause)
            return "pause";
        return player.canTogglePlaying ? "togglePlaying" : "";
    }
    if (action === "play-pause") {
        if (player.isPlaying) {
            if (player.canPause)
                return "pause";
            return player.canTogglePlaying ? "togglePlaying" : "";
        }
        if (player.canPlay)
            return "play";
        return player.canTogglePlaying ? "togglePlaying" : "";
    }
    return "";
}

function canHandleAction(player, action) {
    return actionMethod(player, action).length > 0;
}

function canCycleSource(player) {
    return Boolean(player && hasMetadata(player) && (player.isPlaying || player.canPlay));
}

function nodeProperties(node) {
    if (!node || node.ready === false || !node.properties)
        return {};
    return node.properties;
}

function isPlaybackStream(node) {
    if (!node || !node.isStream)
        return false;

    const properties = nodeProperties(node);
    const mediaClass = text(properties["media.class"] || node.type);
    return node.isSink === true
        || mediaClass.indexOf("Stream/Output/Audio") >= 0
        || mediaClass.indexOf("AudioOutStream") >= 0;
}

function labelKey(label) {
    let key = text(label).toLowerCase();
    key = key.replace(/^org\.mpris\.mediaplayer2\./, "");
    key = key.replace(/\.instance[0-9]+$/, "");
    key = key.replace(/^pipewire alsa \[/, "");
    key = key.replace(/^alsa playback \[/, "");
    key = key.replace(/\]$/, "");
    return key.replace(/[^a-z0-9]+/g, "");
}

function uniqueKeys(values) {
    const result = [];
    for (const value of values) {
        const key = labelKey(value);
        if (key && result.indexOf(key) < 0)
            result.push(key);
    }
    return result;
}

function streamKeys(node) {
    const properties = nodeProperties(node);
    return uniqueKeys([
        properties["application.name"],
        properties["application.process.binary"],
        properties["media.name"],
        properties["node.name"],
        node && node.description,
        node && node.name
    ]);
}

function playerKeys(player) {
    if (!player)
        return [];
    return uniqueKeys([
        player.desktopEntry,
        player.identity,
        player.dbusName
    ]);
}

function keysMatch(first, second) {
    if (first === second)
        return true;
    return first.length >= 4 && second.length >= 4
        && (first.indexOf(second) >= 0 || second.indexOf(first) >= 0);
}

function playerHasPlaybackStream(player, playbackStreams) {
    const candidateKeys = playerKeys(player);
    if (candidateKeys.length === 0)
        return false;

    for (const stream of toArray(playbackStreams)) {
        for (const streamKey of streamKeys(stream)) {
            if (candidateKeys.some(candidateKey => keysMatch(candidateKey, streamKey)))
                return true;
        }
    }
    return false;
}

function playerKey(player) {
    return text(player && (player.dbusName || player.desktopEntry || player.identity));
}

function aliasRoot(player) {
    return text(player && player.dbusName)
        .toLowerCase()
        .replace(/\.instance[0-9]+$/, "");
}

function aliasTrackSignature(player) {
    if (!hasTrackMetadata(player))
        return "";
    return [
        text(player.trackTitle),
        text(player.trackArtist),
        text(player.trackAlbum),
        text(player.trackArtUrl),
        player.isPlaying ? "playing" : "idle"
    ].join("^_");
}

function equivalentAliases(first, second) {
    const firstName = text(first && first.dbusName).toLowerCase();
    const secondName = text(second && second.dbusName).toLowerCase();
    const root = aliasRoot(first);
    if (!root || root !== aliasRoot(second) || firstName === secondName)
        return false;
    const firstInstance = firstName.startsWith(`${root}.instance`);
    const secondInstance = secondName.startsWith(`${root}.instance`);
    if (firstInstance === secondInstance)
        return false;
    const signature = aliasTrackSignature(first);
    return Boolean(signature && signature === aliasTrackSignature(second));
}

function preferredAlias(first, second) {
    const firstInstance = /\.instance[0-9]+$/i.test(text(first && first.dbusName));
    const secondInstance = /\.instance[0-9]+$/i.test(text(second && second.dbusName));
    if (firstInstance !== secondInstance)
        return firstInstance ? first : second;
    return playerKey(first).localeCompare(playerKey(second)) <= 0 ? first : second;
}

function deduplicateAliases(players) {
    const result = [];
    for (const player of toArray(players)) {
        const duplicateIndex = result.findIndex(existing => equivalentAliases(existing, player));
        if (duplicateIndex < 0)
            result.push(player);
        else
            result[duplicateIndex] = preferredAlias(result[duplicateIndex], player);
    }
    return result;
}

function labelFor(player) {
    if (!player)
        return "";
    return text(player.trackTitle || player.identity || player.desktopEntry || player.dbusName);
}

function sourceLabel(player) {
    if (!player)
        return "Media source";
    return text(player.identity || player.desktopEntry || player.dbusName) || "Media source";
}

function playerOrder(player, startedAt, fallback) {
    const key = playerKey(player);
    const value = key && startedAt ? Number(startedAt[key]) : NaN;
    return Number.isFinite(value) ? value : fallback;
}

function orderedSourcePlayers(players, startedAt) {
    const list = deduplicateAliases(players).filter(hasMetadata);
    list.sort((first, second) => {
        if (Boolean(first.isPlaying) !== Boolean(second.isPlaying))
            return first.isPlaying ? -1 : 1;
        if (isProxyPlayer(first) !== isProxyPlayer(second))
            return isProxyPlayer(first) ? 1 : -1;
        if (first.isPlaying && second.isPlaying) {
            const delta = playerOrder(first, startedAt, 1000000)
                - playerOrder(second, startedAt, 1000000);
            if (delta !== 0)
                return delta;
        }
        return labelFor(first).localeCompare(labelFor(second));
    });
    return list;
}

function orderedCyclePlayers(players) {
    const list = deduplicateAliases(players).filter(canCycleSource);
    list.sort((first, second) => {
        if (isProxyPlayer(first) !== isProxyPlayer(second))
            return isProxyPlayer(first) ? 1 : -1;
        return labelFor(first).localeCompare(labelFor(second));
    });
    return list;
}

function selectionRank(player, playbackStreams) {
    const proxy = isProxyPlayer(player);
    const playing = Boolean(player && player.isPlaying);
    const activeStream = playerHasPlaybackStream(player, playbackStreams);

    if (playing && !proxy && activeStream)
        return 0;
    if (playing && !proxy)
        return 1;
    if (playing && proxy && activeStream)
        return 2;
    if (playing && proxy)
        return 3;
    if (activeStream && !proxy)
        return 4;
    if (activeStream)
        return 5;
    if (hasTrackMetadata(player) && !proxy)
        return 6;
    if (hasTrackMetadata(player))
        return 7;
    if (playerCanControl(player) && !proxy)
        return 8;
    if (playerCanControl(player))
        return 9;
    if (hasMetadata(player) && !proxy)
        return 10;
    if (hasMetadata(player))
        return 11;
    return 12;
}

function selectActivePlayer(players, playbackStreams, startedAt, preferredKey) {
    const list = deduplicateAliases(players).filter(player => player && (
        hasMetadata(player) || playerCanControl(player) || player.isPlaying
    ));
    const explicit = text(preferredKey);
    if (explicit) {
        const preferred = list.find(player => playerKey(player) === explicit);
        if (preferred)
            return preferred;
    }

    const indexed = list.map((player, index) => ({ player: player, index: index }));
    indexed.sort((first, second) => {
        const rankDelta = selectionRank(first.player, playbackStreams)
            - selectionRank(second.player, playbackStreams);
        if (rankDelta !== 0)
            return rankDelta;
        if (first.player.isPlaying && second.player.isPlaying) {
            const orderDelta = playerOrder(first.player, startedAt, first.index + 1000000)
                - playerOrder(second.player, startedAt, second.index + 1000000);
            if (orderDelta !== 0)
                return orderDelta;
        }
        const labelDelta = labelFor(first.player).localeCompare(labelFor(second.player));
        return labelDelta !== 0 ? labelDelta : first.index - second.index;
    });
    return indexed.length > 0 && selectionRank(indexed[0].player, playbackStreams) < 12
        ? indexed[0].player
        : null;
}

function playerForAction(players, activePlayer, action, targetKey, startedAt) {
    const list = deduplicateAliases(players);
    const explicit = text(targetKey);
    if (explicit) {
        const targeted = list.find(player => playerKey(player) === explicit);
        if (canHandleAction(targeted, action))
            return targeted;
    }
    if (canHandleAction(activePlayer, action))
        return activePlayer;

    const ordered = orderedSourcePlayers(list, startedAt);
    return ordered.find(player => canHandleAction(player, action)) || null;
}

function cycledPlayer(players, activeKey, delta) {
    const list = orderedCyclePlayers(players);
    if (list.length === 0)
        return null;

    const currentKey = text(activeKey);
    let index = list.findIndex(player => playerKey(player) === currentKey);
    if (index < 0)
        index = delta >= 0 ? -1 : 0;
    const offset = Number(delta) < 0 ? -1 : 1;
    return list[(index + offset + list.length) % list.length];
}

function trackSignature(player) {
    if (!player)
        return "";
    return [
        player.uniqueId || "",
        text(player.trackTitle),
        text(player.trackArtist),
        text(player.trackAlbum),
        text(player.trackArtUrl)
    ].join("^_");
}

function trackChanged(previousSignature, player) {
    return trackSignature(player) !== text(previousSignature);
}

function osdMessage(player, fallback) {
    if (!player)
        return text(fallback);
    const title = text(player.trackTitle);
    const artist = text(player.trackArtist);
    if (title && artist)
        return `${title} — ${artist}`;
    return title || artist || text(fallback);
}
