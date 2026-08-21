.pragma library

function decodeDnd(text, fallback) {
    const normalized = String(text || "").trim();
    if (!normalized)
        return typeof fallback === "boolean" ? fallback : false;

    const value = JSON.parse(normalized);
    if (!value || typeof value !== "object" || value.version !== 1
            || typeof value.dnd !== "boolean")
        throw new Error("notification state has an unsupported format");

    return value.dnd;
}

function encodeDnd(value) {
    if (typeof value !== "boolean")
        throw new Error("DND state must be a boolean");

    return `${JSON.stringify({ "version": 1, "dnd": value })}\n`;
}
