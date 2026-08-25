.pragma library

function hasHeadphoneMarker(value) {
    const normalized = String(value || "").toLowerCase();
    return normalized.includes("headphone")
        || normalized.includes("headset")
        || normalized.includes("earbud")
        || normalized.includes("airpod");
}

function sinkUsesHeadphones(sink) {
    if (!sink || typeof sink !== "object")
        return false;

    const properties = sink.properties || {};
    const candidates = [
        sink.active_port,
        properties["device.form_factor"],
        properties["device.icon_name"],
        properties["device.icon-name"],
        properties["device.product.name"],
        sink.name,
        sink.description
    ];

    return candidates.some(hasHeadphoneMarker);
}

function normalizeBluetoothAddress(value) {
    const normalized = String(value || "")
        .trim()
        .replace(/[-_]/g, ":")
        .toUpperCase();

    return /^([0-9A-F]{2}:){5}[0-9A-F]{2}$/.test(normalized) ? normalized : "";
}

function activeSinkInfo(serializedSinks, defaultSinkName) {
    const sinks = JSON.parse(serializedSinks);
    if (!Array.isArray(sinks))
        throw new Error("pactl sink data is not an array");

    const sink = sinks.find(candidate => candidate && candidate.name === defaultSinkName);
    const properties = sink && sink.properties ? sink.properties : {};

    return {
        headphonesActive: sinkUsesHeadphones(sink),
        bluetoothAddress: normalizeBluetoothAddress(properties["api.bluez5.address"])
    };
}

function activeSinkUsesHeadphones(serializedSinks, defaultSinkName) {
    return activeSinkInfo(serializedSinks, defaultSinkName).headphonesActive;
}
