.pragma library

function parseMode(value) {
    const match = /^(\d+)x(\d+)@([0-9]+(?:\.[0-9]+)?)Hz$/.exec(String(value || ""));
    if (!match)
        return null;

    return {
        width: Number(match[1]),
        height: Number(match[2]),
        refreshRate: Number(match[3])
    };
}

function formatMode(width, height, refreshRate) {
    return `${width}x${height}@${Number(refreshRate)}`;
}

function monitorPayload(serializedMonitors) {
    const monitors = JSON.parse(serializedMonitors);
    if (!Array.isArray(monitors))
        throw new Error("Hyprland monitor data is not an array");
    return monitors;
}

function internalMonitor(monitors) {
    return monitors.find(monitor => monitor
        && monitor.disabled !== true
        && /^eDP(?:-|$)/.test(String(monitor.name || "")));
}

function nativeModes(monitor) {
    const parsed = (Array.isArray(monitor.availableModes) ? monitor.availableModes : [])
        .map(parseMode)
        .filter(mode => mode && mode.width > 0 && mode.height > 0 && mode.refreshRate > 0);
    if (parsed.length === 0)
        throw new Error(`Hyprland reported no usable modes for ${monitor.name}`);

    // Hyprland does not mark the preferred mode in this payload. Match the
    // persistent `highres` policy by treating the largest geometry as native.
    const native = parsed.reduce((best, candidate) => {
        const candidateArea = candidate.width * candidate.height;
        const bestArea = best.width * best.height;
        if (candidateArea !== bestArea)
            return candidateArea > bestArea ? candidate : best;
        if (candidate.width !== best.width)
            return candidate.width > best.width ? candidate : best;
        return candidate.refreshRate > best.refreshRate ? candidate : best;
    });

    return parsed.filter(mode => mode.width === native.width && mode.height === native.height);
}

function policy(serializedMonitors, targetRefreshRate) {
    const monitor = internalMonitor(monitorPayload(serializedMonitors));
    if (!monitor)
        return { applicable: false };

    const modes = nativeModes(monitor);
    const native = modes[0];
    // The adaptive rate may be synthesized; the recovery mode must always be
    // one that the panel advertised at the selected native resolution.
    const fallback = modes.reduce((best, candidate) => {
        const candidateDistance = Math.abs(candidate.refreshRate - targetRefreshRate);
        const bestDistance = Math.abs(best.refreshRate - targetRefreshRate);
        if (candidateDistance !== bestDistance)
            return candidateDistance < bestDistance ? candidate : best;
        return candidate.refreshRate > best.refreshRate ? candidate : best;
    });

    const x = Number.isFinite(Number(monitor.x)) ? Number(monitor.x) : 0;
    const y = Number.isFinite(Number(monitor.y)) ? Number(monitor.y) : 0;
    const scale = Number.isFinite(Number(monitor.scale)) && Number(monitor.scale) > 0
        ? Number(monitor.scale)
        : 1;

    return {
        applicable: true,
        output: String(monitor.name),
        width: native.width,
        height: native.height,
        targetRefreshRate: Number(targetRefreshRate),
        targetMode: formatMode(native.width, native.height, targetRefreshRate),
        fallbackRefreshRate: fallback.refreshRate,
        fallbackMode: formatMode(native.width, native.height, fallback.refreshRate),
        position: `${x}x${y}`,
        scale: scale
    };
}

function monitorExpression(displayPolicy, mode) {
    return `hl.monitor({ output = ${JSON.stringify(displayPolicy.output)}, mode = ${JSON.stringify(mode)}, position = ${JSON.stringify(displayPolicy.position)}, scale = ${displayPolicy.scale} })`;
}

function verifies(serializedMonitors, displayPolicy, expectedRefreshRate) {
    const monitor = monitorPayload(serializedMonitors)
        .find(candidate => candidate && candidate.name === displayPolicy.output && candidate.disabled !== true);
    if (!monitor)
        return false;

    return Number(monitor.width) === displayPolicy.width
        && Number(monitor.height) === displayPolicy.height
        && Math.abs(Number(monitor.refreshRate) - Number(expectedRefreshRate)) <= 0.05;
}

function verificationOutcome(serializedMonitors, displayPolicy, expectedRefreshRate, attempt, maxAttempts) {
    if (verifies(serializedMonitors, displayPolicy, expectedRefreshRate))
        return "accepted";
    return attempt < maxAttempts ? "retry" : "rejected";
}
