function normalizePanelId(value) {
    return String(value || "").trim();
}

function resolveScreenName(requestedScreenName, fallbackScreenName) {
    return String(requestedScreenName || fallbackScreenName || "");
}

function openState(panelId, requestedScreenName, fallbackScreenName) {
    const normalizedId = normalizePanelId(panelId);
    if (!normalizedId)
        return { activePanel: "", screenName: "" };

    return {
        activePanel: normalizedId,
        screenName: resolveScreenName(requestedScreenName, fallbackScreenName)
    };
}

function toggleState(activePanel, activeScreenName, panelId,
                     requestedScreenName, fallbackScreenName) {
    const next = openState(panelId, requestedScreenName, fallbackScreenName);
    if (normalizePanelId(activePanel) === next.activePanel
            && String(activeScreenName || "") === next.screenName) {
        return { activePanel: "", screenName: "" };
    }
    return next;
}
