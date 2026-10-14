.pragma library

function periodicRefreshIntervalMs() {
    return 60 * 60 * 1000;
}

function backendFromOsRelease(text) {
    const match = text.match(/^ID=["']?([^"'\r\n]+)["']?$/m);
    return match && (match[1] === "arch" || match[1] === "fedora") ? match[1] : "unsupported";
}

function officialCommand(backend) {
    return backend === "fedora"
        ? ["/usr/bin/dnf5", "--quiet", "--assumeyes", "--refresh", "repoquery", "--upgrades", "--latest-limit=1", "--queryformat", "%{name}.%{arch}\\n"]
        : ["/usr/bin/checkupdates"];
}

function launchCommand(home, backend) {
    return [
        "/usr/bin/ghostty",
        "-e",
        `${home}/.config/${backend === "fedora" ? "fedora" : "arch"}/update-system.sh`
    ];
}

function lineCount(text) {
    const trimmed = text.trim();
    return trimmed
        ? trimmed.split(/\r?\n/).filter(line => line.trim().length > 0).length
        : 0;
}

function packageCount(text, backend) {
    if (backend !== "fedora")
        return lineCount(text);
    const names = {};
    text.split(/\r?\n/).forEach(line => {
        if (line.trim()) names[line.trim()] = true;
    });
    return Object.keys(names).length;
}

function refreshIsBusy(officialRunning, aurRunning) {
    return officialRunning || aurRunning;
}
