import QtQuick
import Quickshell
import Quickshell.Io
import "ClockDisplay.js" as ClockDisplay
import "ClockFreshness.js" as ClockFreshness

QtObject {
    id: root

    required property var popouts

    readonly property string warsawTimezone: "Europe/Warsaw"
    readonly property int weatherMaxAgeSeconds: 10800
    readonly property int resumeGapSeconds: 300
    readonly property int postResumeWeatherGraceSeconds: 1200
    readonly property string home: Quickshell.env("HOME")
    readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || `${home}/.cache`
    readonly property string locationPath: `${cacheHome}/quickshell-berg/location.json`
    readonly property string formatterPath: Qt.resolvedUrl("scripts/clock-time.py").toString().replace(/^file:\/\//, "")
    readonly property string weatherPath: `${cacheHome}/quickshell-berg/weather.json`
    readonly property string artworkPath: "/var/lib/arts-wallpaper/current.json"

    property var now: new Date()
    property double lastClockUpdateMs: -1
    property double weatherFreshnessGraceUntilMs: -1
    // Keep real instants separate from civil dates used by the display/calendar.
    property var display: null
    property var lastLocation: null
    property string locationStatus: "unavailable"
    readonly property string currentTimezone: display ? display.local.timezone : warsawTimezone
    readonly property var localDate: display ? display.local : null
    readonly property string localFullDate: display ? display.local.fullDate : ""
    readonly property string localFull: display ? display.local.full : ""
    readonly property string locationNote: locationStatus === "fresh" ? ""
        : locationStatus === "stale" ? "last known location" : "location unavailable"
    readonly property string warsawCompact: display ? display.warsaw.compact : ""
    readonly property string warsawFull: display ? display.warsaw.full : ""
    property var weather: null
    property var artwork: null
    property string timezoneError: ""
    property string weatherError: ""
    property string artworkError: ""
    property string health: "loading"
    property string lastError: ""
    property var lastSuccess: null

    readonly property bool panelOpen: popouts.isOpen("clock", "")
    readonly property string panelScreenName: panelOpen ? popouts.screenName : ""
    readonly property bool artworkRotating: artworkRotation.running

    readonly property string barDate: display ? display.local.barDate : ""
    readonly property string barTime: display ? display.local.time : "--:--"
    readonly property string barWarsaw: currentTimezone !== warsawTimezone && warsawCompact
        ? ClockDisplay.warsawLabel(display.local.shortDate, warsawCompact)
        : ""
    readonly property string text: `${barDate} ${barTime}${barWarsaw ? ` | ${barWarsaw}` : ""}`

    readonly property string tooltip: {
        const sections = [
            `Time\nLocal · ${localFull}`
        ];

        if (currentTimezone !== warsawTimezone && warsawFull)
            sections[0] += `\nWarsaw · ${warsawFull}`;

        if (locationNote)
            sections[0] += `\n${currentTimezone} · ${locationNote}`;

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
        const lines = [localFull];
        if (locationNote)
            lines.push(`${currentTimezone} · ${locationNote}`);

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

    function advanceClock(value: var): void {
        const currentMs = value.getTime();

        // A large gap is how a continuously running shell observes suspend.
        if (ClockFreshness.resumeDetected(lastClockUpdateMs, currentMs, resumeGapSeconds))
            weatherFreshnessGraceUntilMs = currentMs + postResumeWeatherGraceSeconds * 1000;

        lastClockUpdateMs = currentMs;
        now = value;
    }

    function openPanel(screenName: string): void {
        if (popouts.openPanel("clock", screenName))
            refresh();
    }

    function closePanel(): void {
        popouts.closePanel("clock");
    }

    function togglePanel(screenName: string): void {
        if (popouts.togglePanel("clock", screenName))
            refresh();
    }

    function updateHealth(): void {
        const errors = [timezoneError, weatherError, artworkError]
            .filter(message => message.length > 0);
        lastError = errors.join("\n");
        if (errors.length === 0) {
            health = "ready";
            lastSuccess = new Date();
        } else {
            health = "stale";
        }
    }

    function consumeDisplay(text: string): void {
        try {
            const value = JSON.parse(text);
            if (!ClockDisplay.validSnapshot(value))
                throw new Error("incomplete clock snapshot");
            display = value;
            lastLocation = value.location;
            locationStatus = value.locationStatus;
            timezoneError = "";
        } catch (error) {
            timezoneError = `Clock formatter returned invalid output: ${error}`;
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

        const currentMs = now.getTime();
        const age = ClockFreshness.cacheAgeSeconds(weather.updated_at, currentMs);
        const stale = ClockFreshness.cacheIsStale(
            weather.updated_at,
            currentMs,
            weatherMaxAgeSeconds
        );

        if (stale && !ClockFreshness.withinGracePeriod(currentMs, weatherFreshnessGraceUntilMs))
            weatherError = `Weather cache is stale (${Math.max(0, Math.floor(age / 60))} minutes old)`;
        else {
            weatherError = "";
            if (!stale)
                weatherFreshnessGraceUntilMs = -1;
        }
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
        advanceClock(new Date());
        locationFile.reload();
        displayQuery.refresh();
        weatherFile.reload();
        artworkFile.reload();
        validateWeatherAge();
    }

    function rotateArtwork(): bool {
        if (artworkRotation.running)
            return false;

        artworkRotation.refresh();
        return true;
    }

    readonly property ProcessJob artworkRotation: ProcessJob {
        command: [
            "/usr/bin/systemctl",
            "--user",
            "restart",
            "arts-wallpaper.service"
        ]
        runOnStart: false
        timeoutMs: 300000
        onSucceeded: (exitCode, output, errorOutput) => artworkFile.reload()
        onFailed: (message, exitCode, output, errorOutput) => {
            root.artworkError = `Artwork rotation failed: ${message}`;
            root.updateHealth();
        }
    }

    readonly property SystemClock clock: SystemClock {
        precision: SystemClock.Minutes
        onDateChanged: {
            root.advanceClock(date);
            root.displayQuery.refresh();
            root.validateWeatherAge();
        }
    }

    readonly property ProcessJob displayQuery: ProcessJob {
        command: [
            "/usr/bin/python3", root.formatterPath,
            "--epoch", String(root.now.getTime() / 1000),
            "--location-cache", root.locationPath,
            "--fallback-location", JSON.stringify(root.lastLocation)
        ]
        runOnStart: false
        timeoutMs: 3000
        onSucceeded: (exitCode, output, errorOutput) => root.consumeDisplay(output)
        onFailed: (message, exitCode, output, errorOutput) => {
            root.timezoneError = `Clock formatter failed: ${message}`;
            root.updateHealth();
        }
    }

    readonly property FileView locationFile: FileView {
        path: root.locationPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.displayQuery.refresh()
        onLoadFailed: error => root.displayQuery.refresh()
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

    Component.onCompleted: refresh()
}
