function finiteNumber(value, fallback) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
}

function clamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(maximum, value));
}

function stateForShow(iconKey, rawMessage, rawValue, rawMaximum, rawDuration) {
    const hasProgress = rawValue !== undefined && rawValue !== null && String(rawValue) !== "";
    const maximum = Math.max(1, finiteNumber(rawMaximum, 100));
    const value = hasProgress
        ? clamp(finiteNumber(rawValue, 0), 0, maximum)
        : 0;
    const duration = Math.round(clamp(finiteNumber(rawDuration, 1200), 0, 60000));
    let message = rawMessage === undefined || rawMessage === null
        ? ""
        : String(rawMessage);

    if (hasProgress && !message)
        message = `${Math.round(value * 100 / maximum)}%`;

    return {
        iconKey: String(iconKey || "warning"),
        message: message,
        value: value,
        maximum: maximum,
        hasProgress: hasProgress,
        duration: duration
    };
}

function stateForPayload(payloadJson) {
    const payload = JSON.parse(payloadJson || "{}");
    if (!payload || typeof payload !== "object" || Array.isArray(payload))
        throw new Error("OSD payload must be an object");

    const state = stateForShow(
        payload.icon,
        payload.message,
        payload.value,
        payload.max,
        payload.duration
    );
    state.screenName = String(payload.screen || "");
    return state;
}
