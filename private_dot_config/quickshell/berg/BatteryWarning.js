function normalizedPercentage(value) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed) || parsed < 0)
        return -1;
    return Math.round(parsed <= 1 ? parsed * 100 : parsed);
}

function evaluate(rawPercentage, batteryAvailable, onBattery, discharging,
                  alreadyNotified, warningThreshold, resetThreshold) {
    const percentage = normalizedPercentage(rawPercentage);
    const warned = Boolean(alreadyNotified);
    const threshold = Number.isFinite(Number(warningThreshold))
        ? Number(warningThreshold)
        : 10;
    const reset = Math.max(
        threshold + 1,
        Number.isFinite(Number(resetThreshold)) ? Number(resetThreshold) : 15
    );

    if (!batteryAvailable || percentage < 0) {
        return {
            percentage: percentage,
            notify: false,
            notified: warned
        };
    }

    if (!onBattery || !discharging) {
        return {
            percentage: percentage,
            notify: false,
            notified: false
        };
    }

    if (percentage >= reset) {
        return {
            percentage: percentage,
            notify: false,
            notified: false
        };
    }

    const shouldNotify = percentage <= threshold && !warned;
    return {
        percentage: percentage,
        notify: shouldNotify,
        notified: warned || shouldNotify
    };
}
