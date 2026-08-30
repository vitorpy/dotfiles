.pragma library

function periodicRefreshIntervalMs() {
    return 60 * 60 * 1000;
}

function launchCommand(home) {
    return [
        "/usr/bin/ghostty",
        "-e",
        `${home}/.config/arch/update-system.sh`
    ];
}

function lineCount(text) {
    const trimmed = text.trim();
    return trimmed
        ? trimmed.split(/\r?\n/).filter(line => line.trim().length > 0).length
        : 0;
}

function refreshIsBusy(officialRunning, aurRunning) {
    return officialRunning || aurRunning;
}
