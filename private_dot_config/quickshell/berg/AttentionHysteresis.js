function highValueVisible(rawValue, currentlyVisible, showAbove, hideAtOrBelow) {
    const value = Number(rawValue);
    const showThreshold = Number(showAbove);
    const hideThreshold = Number(hideAtOrBelow);

    if (!Number.isFinite(value)
            || !Number.isFinite(showThreshold)
            || !Number.isFinite(hideThreshold)
            || hideThreshold >= showThreshold) {
        return Boolean(currentlyVisible);
    }

    if (value > showThreshold)
        return true;
    if (value <= hideThreshold)
        return false;
    return Boolean(currentlyVisible);
}
