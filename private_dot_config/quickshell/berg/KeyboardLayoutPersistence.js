.pragma library

function normalizeLayout(value) {
    const layout = String(value || "");
    if (!layout)
        return "?";
    if (/Polish|Polski|^pl/i.test(layout))
        return "PL";
    if (/intl|English|^US/i.test(layout))
        return "EN";
    return layout;
}

function layoutId(value) {
    const layout = normalizeLayout(value);
    if (layout === "PL")
        return 0;
    if (layout === "EN")
        return 1;
    return -1;
}

function encodeState(value) {
    const layout = normalizeLayout(value);
    if (layoutId(layout) < 0)
        throw new Error(`unsupported keyboard layout: ${layout}`);
    return `${JSON.stringify({ "version": 1, "layout": layout })}\n`;
}

function decodeState(serialized) {
    const text = String(serialized || "").trim();
    if (!text)
        return { layout: "", shouldSeed: true };

    const parsed = JSON.parse(text);
    if (!parsed || parsed.version !== 1 || typeof parsed.layout !== "string")
        throw new Error("keyboard layout state has an unsupported format");

    const layout = normalizeLayout(parsed.layout);
    if (layoutId(layout) < 0)
        throw new Error(`unsupported keyboard layout: ${layout}`);
    return { layout: layout, shouldSeed: false };
}
