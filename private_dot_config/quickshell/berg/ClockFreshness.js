.pragma library

function resumeDetected(previousMs, currentMs, minimumGapSeconds) {
    if (!Number.isFinite(previousMs) || !Number.isFinite(currentMs)
            || !Number.isFinite(minimumGapSeconds) || previousMs < 0
            || minimumGapSeconds < 0)
        return false;

    return currentMs - previousMs > minimumGapSeconds * 1000;
}

function cacheAgeSeconds(updatedAtSeconds, currentMs) {
    return Math.floor(currentMs / 1000) - updatedAtSeconds;
}

function cacheIsStale(updatedAtSeconds, currentMs, maximumAgeSeconds) {
    const age = cacheAgeSeconds(updatedAtSeconds, currentMs);
    return age < 0 || age > maximumAgeSeconds;
}

function withinGracePeriod(currentMs, graceUntilMs) {
    return Number.isFinite(graceUntilMs) && currentMs < graceUntilMs;
}
