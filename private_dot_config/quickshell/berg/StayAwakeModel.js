.pragma library

function nextEnabled(current, action) {
    const normalizedAction = String(action || "").trim().toLowerCase();
    if (normalizedAction === "enable")
        return true;
    if (normalizedAction === "disable")
        return false;
    if (normalizedAction === "toggle")
        return !Boolean(current);
    throw new Error(`unknown stay-awake action: ${normalizedAction}`);
}

function encodeState(enabled, sessionToken) {
    const normalizedToken = String(sessionToken || "").trim();
    if (!normalizedToken)
        throw new Error("stay-awake session token is empty");

    return JSON.stringify({
        version: 1,
        sessionToken: normalizedToken,
        enabled: Boolean(enabled)
    }) + "\n";
}

function decodeState(serialized, currentSessionToken) {
    const normalizedToken = String(currentSessionToken || "").trim();
    if (!normalizedToken)
        throw new Error("stay-awake session token is empty");

    const text = String(serialized || "").trim();
    if (!text)
        return { enabled: false, shouldSeed: true };

    const parsed = JSON.parse(text);
    if (!parsed || parsed.version !== 1
            || typeof parsed.sessionToken !== "string"
            || typeof parsed.enabled !== "boolean") {
        throw new Error("invalid stay-awake state");
    }

    if (parsed.sessionToken !== normalizedToken)
        return { enabled: false, shouldSeed: true };
    return { enabled: parsed.enabled, shouldSeed: false };
}

function status(enabled, loaded) {
    return {
        enabled: Boolean(enabled),
        loaded: Boolean(loaded),
        scope: "session",
        mechanism: "wayland-idle-inhibit"
    };
}
