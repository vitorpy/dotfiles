.pragma library

function text(value) {
    return String(value || "").trim();
}

function propertiesFor(node) {
    return node && node.properties ? node.properties : {};
}

function mediaClass(node) {
    return text(propertiesFor(node)["media.class"]);
}

function isJabra(node) {
    if (!node)
        return false;

    const properties = propertiesFor(node);
    const identity = [
        node.name,
        node.description,
        node.nickname,
        properties["device.description"],
        properties["device.product.name"],
        properties["device.vendor.name"]
    ].map(text).join(" ").toLowerCase();

    return identity.includes("jabra") || identity.includes("gn netcom");
}

function isCandidate(node, kind) {
    if (!node || node.isStream || !node.audio)
        return false;

    if (kind === "sink")
        return Boolean(node.isSink);

    if (kind !== "source" || node.isSink)
        return false;

    const candidateClass = mediaClass(node).toLowerCase();
    return candidateClass.startsWith("audio/source")
        || candidateClass === ""
        || candidateClass === "source";
}

function labelFor(node, kind) {
    if (!node)
        return kind === "source" ? "Unknown input" : "Unknown output";

    const properties = propertiesFor(node);
    return text(node.description)
        || text(properties["device.description"])
        || text(node.nickname)
        || text(node.name)
        || (kind === "source" ? "Unknown input" : "Unknown output");
}

function defaultSinkTransition(previousName, initialized, sink) {
    const name = text(sink && sink.name);
    return {
        name: name,
        initialized: Boolean(initialized) || name.length > 0,
        shouldAnnounce: Boolean(initialized)
            && name.length > 0
            && name !== text(previousName),
        label: labelFor(sink, "sink")
    };
}

function compareDevices(left, right) {
    if (left.jabra !== right.jabra)
        return left.jabra ? -1 : 1;
    if (left.active !== right.active)
        return left.active ? -1 : 1;
    return left.label.localeCompare(right.label, undefined, { sensitivity: "base" });
}

function snapshot(nodes, kind, defaultNode) {
    const values = nodes && typeof nodes.length === "number" ? nodes : [];
    const seenNames = {};
    const devices = [];

    for (let index = 0; index < values.length; ++index) {
        const node = values[index];
        if (!isCandidate(node, kind))
            continue;

        const name = text(node.name);
        if (!name || seenNames[name])
            continue;
        seenNames[name] = true;

        devices.push({
            node: node,
            id: Number(node.id),
            name: name,
            label: labelFor(node, kind),
            jabra: isJabra(node),
            active: node === defaultNode || (defaultNode && name === text(defaultNode.name))
        });
    }

    devices.sort(compareDevices);
    return devices;
}
