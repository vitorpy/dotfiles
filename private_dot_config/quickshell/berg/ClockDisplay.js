.pragma library

function warsawLabel(localDate, warsawCompact) {
    const match = /^(\d{2}\.\d{2}) (\d{2}:\d{2})$/.exec(warsawCompact);
    if (!match)
        return `Warsaw ${warsawCompact}`;

    return match[1] === localDate
        ? `Warsaw ${match[2]}`
        : `Warsaw ${match[1]} ${match[2]}`;
}
