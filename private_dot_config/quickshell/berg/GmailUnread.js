.pragma library

function periodicRefreshIntervalMs() {
    return 60 * 1000;
}

function nonNegativeInteger(value, label) {
    if (!Number.isInteger(value) || value < 0)
        throw new Error(`${label} must be a non-negative integer`);
    return value;
}

function parsePayload(text) {
    const value = JSON.parse(text);
    if (!value || typeof value !== "object" || Array.isArray(value))
        throw new Error("result must be an object");
    if (typeof value.configured !== "boolean")
        throw new Error("configured must be a boolean");

    if (!value.configured) {
        return {
            configured: false,
            countField: "threadsUnread",
            total: 0,
            accounts: []
        };
    }

    if (value.countField !== "threadsUnread" && value.countField !== "messagesUnread")
        throw new Error("countField is invalid");
    if (!Array.isArray(value.accounts) || value.accounts.length === 0)
        throw new Error("accounts must be a non-empty array");

    let accountSum = 0;
    for (const account of value.accounts) {
        if (!account || typeof account !== "object" || Array.isArray(account))
            throw new Error("account result must be an object");
        if (typeof account.name !== "string" || account.name.length === 0)
            throw new Error("account name is invalid");
        if (!Array.isArray(account.labels) || account.labels.length === 0)
            throw new Error(`labels for ${account.name} must be a non-empty array`);

        let labelSum = 0;
        for (const label of account.labels) {
            if (!label || typeof label !== "object" || Array.isArray(label))
                throw new Error(`label result for ${account.name} must be an object`);
            if (typeof label.id !== "string" || label.id.length === 0
                    || typeof label.name !== "string" || label.name.length === 0)
                throw new Error(`label identity for ${account.name} is invalid`);
            labelSum += nonNegativeInteger(label.unread, `unread count for ${account.name}/${label.name}`);
        }

        const accountTotal = nonNegativeInteger(account.total, `total for ${account.name}`);
        if (accountTotal !== labelSum)
            throw new Error(`total for ${account.name} does not match its labels`);
        accountSum += accountTotal;
    }

    const total = nonNegativeInteger(value.total, "total");
    if (total !== accountSum)
        throw new Error("total does not match the account totals");

    return {
        configured: true,
        countField: value.countField,
        total: total,
        accounts: value.accounts
    };
}

function badgeText(total) {
    return total > 99 ? "99+" : total.toString();
}

function tooltip(result) {
    if (!result.configured)
        return "Gmail unread is not configured";

    const unit = result.countField === "threadsUnread" ? "threads" : "messages";
    const lines = [`Gmail · ${result.total} unread ${unit}`];
    let labelCount = 0;

    for (const account of result.accounts) {
        lines.push(`${account.name} · ${account.total}`);
        for (const label of account.labels) {
            lines.push(`  ${label.name} · ${label.unread}`);
            labelCount += 1;
        }
    }

    if (labelCount > 1)
        lines.push("Configured labels are summed; overlapping labels may count the same item more than once");
    lines.push("Click to refresh");
    return lines.join("\n");
}
