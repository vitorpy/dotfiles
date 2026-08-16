import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string warsawTimezone: "Europe/Warsaw"
    readonly property int weatherMaxAgeSeconds: 10800
    readonly property string home: Quickshell.env("HOME")
    readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || `${home}/.cache`
    readonly property string weatherPath: `${cacheHome}/quickshell-berg/weather.json`
    readonly property string artworkPath: "/var/lib/arts-wallpaper/current.json"

    property var now: new Date()
    property string currentTimezone: warsawTimezone
    property string warsawCompact: ""
    property string warsawFull: ""
    property var weather: null
    property var artwork: null
    property bool panelOpen: false
    property string panelScreenName: ""
    property string timezoneError: ""
    property string warsawError: ""
    property string weatherError: ""
    property string artworkError: ""
    property string health: "loading"
    property string lastError: ""
    property var lastSuccess: null

    readonly property string text: {
        const local = Qt.formatDateTime(now, "ddd, dd.MM HH:mm");
        return currentTimezone !== warsawTimezone && warsawCompact
            ? `${local} (${warsawCompact})`
            : local;
    }

    readonly property string tooltip: {
        const sections = [
            `Time\nLocal · ${Qt.formatDateTime(now, "dddd, dd MMMM · HH:mm")}`
        ];

        if (currentTimezone !== warsawTimezone && warsawFull)
            sections[0] += `\nWarsaw · ${warsawFull}`;

        const weatherText = weatherTooltip();
        if (weatherText)
            sections.push(weatherText);

        const artworkText = artworkTooltip();
        if (artworkText)
            sections.push(artworkText);

        if (lastError)
            sections.push(`Status\n${lastError}`);

        return sections.join("\n\n");
    }

    readonly property string compactTooltip: {
        const lines = [Qt.formatDateTime(now, "dddd, d MMMM · HH:mm")];

        if (currentTimezone !== warsawTimezone && warsawCompact)
            lines.push(`Warsaw · ${warsawCompact}`);

        if (weather)
            lines.push(`${weather.current.condition} · ${rounded(weather.current.temperature_c)} °C in ${weather.location.city}`);

        lines.push("Left click: open calendar · Right click: refresh");
        return lines.join("\n");
    }

    function finiteNumber(value: var): bool {
        return typeof value === "number" && Number.isFinite(value);
    }

    function rounded(value: real): string {
        return Math.round(value).toString();
    }

    function fallbackScreenName(): string {
        return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "";
    }

    function screenExists(name: string): bool {
        for (let index = 0; index < Quickshell.screens.length; ++index) {
            if (Quickshell.screens[index].name === name)
                return true;
        }
        return false;
    }

    function openPanel(screenName: string): void {
        panelScreenName = screenName || fallbackScreenName();
        panelOpen = true;
        refresh();
    }

    function closePanel(): void {
        panelOpen = false;
        panelScreenName = "";
    }

    function togglePanel(screenName: string): void {
        if (panelOpen && panelScreenName === screenName)
            closePanel();
        else
            openPanel(screenName);
    }

    function rehomeMissingScreen(): void {
        if (panelOpen && !screenExists(panelScreenName))
            panelScreenName = fallbackScreenName();
    }

    function updateHealth(): void {
        const errors = [timezoneError, warsawError, weatherError, artworkError]
            .filter(message => message.length > 0);
        lastError = errors.join("\n");
        if (errors.length === 0) {
            health = "ready";
            lastSuccess = new Date();
        } else {
            health = "stale";
        }
    }

    function consumeTimezone(text: string): void {
        const value = text.trim();
        if (!value) {
            timezoneError = "Timezone could not be determined; assuming Europe/Warsaw";
            currentTimezone = warsawTimezone;
        } else {
            currentTimezone = value;
            timezoneError = "";
        }
        refreshWarsaw();
        updateHealth();
    }

    function refreshWarsaw(): void {
        if (currentTimezone === warsawTimezone) {
            warsawCompact = "";
            warsawFull = "";
            warsawError = "";
            updateHealth();
            return;
        }
        warsawQuery.refresh();
    }

    function consumeWarsaw(text: string): void {
        const lines = text.split(/\r?\n/);
        if (lines.length < 2 || !lines[0].trim() || !lines[1].trim()) {
            warsawError = "Warsaw time formatter returned incomplete output";
        } else {
            warsawCompact = lines[0].trim();
            warsawFull = lines[1].trim();
            warsawError = "";
        }
        updateHealth();
    }

    function consumeWeather(text: string): void {
        try {
            const value = JSON.parse(text);
            const location = value.location;
            const current = value.current;
            const next = value.next_hour;
            const valid = value && typeof value === "object"
                && location && typeof location.city === "string" && location.city.length > 0
                && typeof location.country_code === "string" && location.country_code.length === 2
                && current && typeof current.condition === "string" && current.condition.length > 0
                && finiteNumber(current.temperature_c)
                && finiteNumber(current.apparent_temperature_c)
                && finiteNumber(current.wind_speed_kmh)
                && next && typeof next.time === "string" && next.time.length > 0
                && typeof next.condition === "string" && next.condition.length > 0
                && finiteNumber(next.temperature_c)
                && finiteNumber(next.precipitation_probability)
                && finiteNumber(value.updated_at);

            if (!valid) {
                weather = null;
                weatherError = "Weather cache is malformed";
            } else {
                weather = value;
                validateWeatherAge();
            }
        } catch (error) {
            weather = null;
            weatherError = `Weather cache is malformed: ${error}`;
        }
        updateHealth();
    }

    function validateWeatherAge(): void {
        if (!weather)
            return;
        const age = Math.floor(now.getTime() / 1000) - weather.updated_at;
        if (age < 0 || age > weatherMaxAgeSeconds)
            weatherError = `Weather cache is stale (${Math.max(0, Math.floor(age / 60))} minutes old)`;
        else
            weatherError = "";
        updateHealth();
    }

    function consumeArtwork(text: string): void {
        try {
            const value = JSON.parse(text);
            if (!value || typeof value !== "object" || typeof value.title !== "string" || !value.title) {
                artwork = null;
                artworkError = "Artwork metadata is malformed";
            } else {
                artwork = value;
                artworkError = "";
            }
        } catch (error) {
            artwork = null;
            artworkError = `Artwork metadata is malformed: ${error}`;
        }
        updateHealth();
    }

    function weatherTooltip(): string {
        if (!weather)
            return "";
        const nextLabel = /T[0-9]{2}:[0-9]{2}$/.test(weather.next_hour.time)
            ? weather.next_hour.time.split("T")[1]
            : "Next hour";
        return [
            `Weather · ${weather.location.city}, ${weather.location.country_code}`,
            `Now · ${weather.current.condition} · ${rounded(weather.current.temperature_c)} °C · feels ${rounded(weather.current.apparent_temperature_c)} °C`,
            `${nextLabel} · ${weather.next_hour.condition} · ${rounded(weather.next_hour.temperature_c)} °C · precip. ${rounded(weather.next_hour.precipitation_probability)}%`,
            `Wind · ${rounded(weather.current.wind_speed_kmh)} km/h`
        ].join("\n");
    }

    function artworkTooltip(): string {
        if (!artwork)
            return "";
        const lines = ["Artwork", artwork.title];
        const creatorAndDate = [artwork.creator, artwork.date]
            .filter(value => typeof value === "string" && value.length > 0)
            .join(" — ");
        if (creatorAndDate)
            lines.push(creatorAndDate);
        if (typeof artwork.provider_name === "string" && artwork.provider_name)
            lines.push(artwork.provider_name);
        if (typeof artwork.attribution === "string" && artwork.attribution
                && artwork.attribution !== artwork.provider_name)
            lines.push(`Credit: ${artwork.attribution}`);
        if (typeof artwork.rights === "string" && artwork.rights)
            lines.push(`Rights: ${artwork.rights}`);
        return lines.join("\n");
    }

    function refresh(): void {
        now = new Date();
        timezoneQuery.refresh();
        weatherFile.reload();
        artworkFile.reload();
        validateWeatherAge();
    }

    readonly property SystemClock clock: SystemClock {
        precision: SystemClock.Minutes
        onDateChanged: {
            root.now = date;
            root.refreshWarsaw();
            root.validateWeatherAge();
        }
    }

    readonly property ProcessJob timezoneQuery: ProcessJob {
        command: ["/usr/bin/timedatectl", "show", "--property=Timezone", "--value"]
        runOnStart: false
        timeoutMs: 3000
        onSucceeded: (exitCode, output, errorOutput) => root.consumeTimezone(output)
        onFailed: (message, exitCode, output, errorOutput) => {
            root.currentTimezone = root.warsawTimezone;
            root.timezoneError = `Timezone lookup failed: ${message}`;
            root.refreshWarsaw();
            root.updateHealth();
        }
    }

    readonly property ProcessJob warsawQuery: ProcessJob {
        command: [
            "/usr/bin/env",
            `TZ=${root.warsawTimezone}`,
            "/usr/bin/date",
            "+%d.%m %H:%M\\n%A, %d %B · %H:%M"
        ]
        runOnStart: false
        timeoutMs: 2000
        onSucceeded: (exitCode, output, errorOutput) => root.consumeWarsaw(output)
        onFailed: (message, exitCode, output, errorOutput) => {
            root.warsawError = `Warsaw time lookup failed: ${message}`;
            root.updateHealth();
        }
    }

    readonly property FileView weatherFile: FileView {
        id: weatherFile

        path: root.weatherPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.consumeWeather(text())
        onLoadFailed: error => {
            root.weather = null;
            root.weatherError = `Weather cache is unavailable: ${FileViewError.toString(error)}`;
            root.updateHealth();
        }
    }

    readonly property FileView artworkFile: FileView {
        id: artworkFile

        path: root.artworkPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.consumeArtwork(text())
        onLoadFailed: error => {
            root.artwork = null;
            root.artworkError = error === FileViewError.FileNotFound
                ? ""
                : `Artwork metadata is unavailable: ${FileViewError.toString(error)}`;
            root.updateHealth();
        }
    }

    readonly property Connections screenChanges: Connections {
        target: Quickshell

        function onScreensChanged(): void {
            root.rehomeMissingScreen();
        }
    }

    Component.onCompleted: refresh()
}
