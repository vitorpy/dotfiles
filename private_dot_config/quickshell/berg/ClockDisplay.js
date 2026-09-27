.pragma library

function validClock(value) {
    return value && typeof value === "object"
        && ["timezone", "isoDate", "shortDate", "barDate", "time", "fullDate", "full", "compact"]
            .every(key => typeof value[key] === "string" && value[key].length > 0)
        && Number.isInteger(value.year) && value.year >= 1 && value.year <= 9999
        && Number.isInteger(value.month) && value.month >= 1 && value.month <= 12
        && Number.isInteger(value.day) && value.day >= 1 && value.day <= 31;
}

function validSnapshot(value) {
    return value && Number.isFinite(value.epoch)
        && validClock(value.local) && validClock(value.warsaw)
        && ["fresh", "stale", "unavailable"].indexOf(value.locationStatus) >= 0
        && (value.location === null || (value.location
            && value.location.timezone === value.local.timezone
            && Number.isFinite(value.location.updated_at)));
}

// These Date objects are only calendar coordinates. Never interpret them as
// local instants or compare their epoch with freshness timestamps.
function calendarMonth(civil, offset) {
    return new Date(Date.UTC(civil ? civil.year : 2000, (civil ? civil.month : 1) - 1 + offset, 1));
}

function calendarCell(month, index) {
    const firstWeekday = (month.getUTCDay() + 6) % 7;
    return new Date(Date.UTC(month.getUTCFullYear(), month.getUTCMonth(), index - firstWeekday + 1));
}

function isToday(day, civil) {
    return civil !== null && day.getUTCFullYear() === civil.year
        && day.getUTCMonth() + 1 === civil.month && day.getUTCDate() === civil.day;
}

function warsawLabel(localDate, warsawCompact) {
    const match = /^(\d{2}\.\d{2}) (\d{2}:\d{2})$/.exec(warsawCompact);
    if (!match)
        return `Warsaw ${warsawCompact}`;

    return match[1] === localDate
        ? `Warsaw ${match[2]}`
        : `Warsaw ${match[1]} ${match[2]}`;
}
