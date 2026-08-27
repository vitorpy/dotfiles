import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "NotificationPersistence.js" as NotificationPersistence

Scope {
    id: root

    required property var popouts

    readonly property int historyLimit: 100
    readonly property int maxVisibleGroups: 5
    readonly property int defaultTimeoutMs: 5000
    readonly property string dndStatePath: Quickshell.statePath("notifications.json")

    property var entries: []
    property int revision: 0
    property bool dndStateLoaded: false

    readonly property bool centerOpen: popouts.isOpen("notifications", "")
    readonly property string centerScreenName: centerOpen ? popouts.screenName : ""
    readonly property bool dnd: !dndStateLoaded || persisted.dnd
    readonly property int count: {
        const ignored = revision;
        return entries.filter(entry => entry.inCenter).length;
    }
    readonly property int unreadCount: {
        const ignored = revision;
        return entries.filter(entry => entry.inCenter && entry.unread).length;
    }
    readonly property string badgeText: unreadCount > 99 ? "99+" : (unreadCount > 0 ? unreadCount.toString() : "")
    readonly property string tooltip: {
        const summary = count === 0
            ? "No notifications"
            : `${count} notification${count === 1 ? "" : "s"} · ${unreadCount} unread`;
        return `${summary}\nDo Not Disturb: ${dnd ? "ON" : "OFF"}\nLeft click: open center\nRight click: toggle DND`;
    }
    readonly property var centerGroups: {
        const ignored = revision;
        return buildGroups(entries.filter(entry => entry.inCenter), false);
    }

    signal received(var entry)

    function touch(): void {
        revision += 1;
        entries = entries.slice();
    }

    function restoreDndState(): void {
        const text = dndStateFile.text();
        let shouldSeed = !text.trim();

        try {
            persisted.dnd = NotificationPersistence.decodeDnd(text, persisted.dnd);
        } catch (error) {
            console.warn(`Notification state: unable to restore DND: ${error}`);
            shouldSeed = true;
        }

        dndStateLoaded = true;
        if (shouldSeed)
            persistDndState();
    }

    function persistDndState(): void {
        if (!dndStateLoaded)
            return;
        dndStateFile.setText(NotificationPersistence.encodeDnd(persisted.dnd));
    }

    function applicationKey(notification: var): string {
        if (!notification)
            return "unknown";
        return notification.desktopEntry || notification.appName || "unknown";
    }

    function applicationName(notification: var): string {
        if (!notification)
            return "Unknown application";
        return notification.appName || notification.desktopEntry || "Unknown application";
    }

    function hint(notification: var, name: string): var {
        if (!notification || !notification.hints)
            return undefined;
        return notification.hints[name];
    }

    function stackKey(notification: var): string {
        const dunstTag = hint(notification, "x-dunst-stack-tag");
        const canonicalTag = hint(notification, "x-canonical-private-synchronous");
        const tag = dunstTag !== undefined && dunstTag !== "" ? dunstTag : canonicalTag;
        return tag === undefined || tag === ""
            ? ""
            : `${applicationKey(notification)}:${String(tag)}`;
    }

    function timeoutFor(notification: var): int {
        if (!notification || notification.urgency === NotificationUrgency.Critical)
            return 0;
        if (notification.expireTimeout === 0)
            return 0;
        if (notification.expireTimeout > 0)
            return Math.max(1, Math.round(notification.expireTimeout));
        return defaultTimeoutMs;
    }

    function focusedScreenName(): string {
        return popouts.focusedScreenName();
    }

    function screenExists(name: string): bool {
        for (let index = 0; index < Quickshell.screens.length; ++index) {
            if (Quickshell.screens[index].name === name)
                return true;
        }
        return false;
    }

    function rehomeMissingScreens(): void {
        const fallback = focusedScreenName();
        let changed = false;
        for (const entry of entries) {
            if (entry.popupVisible && !screenExists(entry.screenName)) {
                entry.screenName = fallback;
                changed = true;
            }
        }
        if (changed)
            touch();
    }

    function readIds(): var {
        return Array.isArray(persisted.readIds) ? persisted.readIds : [];
    }

    function rememberRead(id: int): void {
        const ids = readIds();
        if (ids.indexOf(id) < 0)
            persisted.readIds = ids.concat([id]);
    }

    function forgetRead(id: int): void {
        persisted.readIds = readIds().filter(value => value !== id);
    }

    function findById(id: int): var {
        return entries.find(entry => entry.notification && entry.notification.id === id) || null;
    }

    function findByStackKey(key: string): var {
        if (!key)
            return null;
        return entries.find(entry => entry.stackKey === key) || null;
    }

    function receiveNotification(notification: var): void {
        notification.tracked = true;

        let entry = findById(notification.id);
        const newStackKey = stackKey(notification);
        const stackedEntry = findByStackKey(newStackKey);
        if (!entry && stackedEntry && stackedEntry.notification !== notification)
            stackedEntry.notification.expire();

        if (entry) {
            entry.notification = notification;
            entry.stackKey = newStackKey;
            entry.timeoutMs = timeoutFor(notification);
            entry.inCenter = !notification.transient;
            entry.screenName = focusedScreenName();
            entry.popupVisible = !notification.lastGeneration && !dnd;
            if (!notification.lastGeneration && entry.inCenter) {
                entry.unread = !centerOpen;
                if (centerOpen)
                    rememberRead(notification.id);
            }
            entry.restartPopupTimer();
            touch();
            received(entry);
            return;
        }

        const wasRead = readIds().indexOf(notification.id) >= 0;
        entry = entryComponent.createObject(root, {
            "notification": notification,
            "receivedAt": Date.now(),
            "screenName": focusedScreenName(),
            "stackKey": newStackKey,
            "timeoutMs": timeoutFor(notification),
            "inCenter": !notification.transient,
            "unread": !notification.transient && !centerOpen && !wasRead,
            "popupVisible": !notification.lastGeneration && !dnd
        });

        if (!entry) {
            notification.expire();
            console.warn("Notification state: unable to allocate notification entry");
            return;
        }

        entries = [entry].concat(entries);
        if (centerOpen && entry.inCenter)
            rememberRead(notification.id);
        entry.restartPopupTimer();
        enforceHistoryLimit();
        touch();
        received(entry);
    }

    function refreshEntry(entry: var): void {
        if (!entry || !entry.notification)
            return;
        entry.stackKey = stackKey(entry.notification);
        entry.timeoutMs = timeoutFor(entry.notification);
        entry.inCenter = !entry.notification.transient;
        touch();
    }

    function removeEntry(entry: var): void {
        if (!entry || entries.indexOf(entry) < 0)
            return;
        const id = entry.notification ? entry.notification.id : -1;
        entries = entries.filter(candidate => candidate !== entry);
        if (id >= 0)
            forgetRead(id);
        revision += 1;
        Qt.callLater(() => entry.destroy());
    }

    function hidePopup(entry: var): void {
        if (!entry || !entry.popupVisible)
            return;
        entry.popupVisible = false;
        if (entry.notification && entry.notification.transient)
            entry.notification.expire();
        touch();
    }

    function enforceHistoryLimit(): void {
        const retained = entries.filter(entry => entry.inCenter);
        for (let index = historyLimit; index < retained.length; ++index) {
            const entry = retained[index];
            if (entry.notification)
                entry.notification.expire();
        }
    }

    function setDnd(value: bool): void {
        if (persisted.dnd === value)
            return;
        persisted.dnd = value;
        persistDndState();
        if (value) {
            for (const entry of entries) {
                entry.popupVisible = false;
                entry.popupTimer.stop();
            }
        }
        touch();
    }

    function toggleDnd(): void {
        setDnd(!dnd);
    }

    function openCenter(screenName: string): void {
        if (popouts.openPanel("notifications", screenName))
            markAllRead();
    }

    function closeCenter(): void {
        popouts.closePanel("notifications");
    }

    function toggleCenter(screenName: string): void {
        if (popouts.togglePanel("notifications", screenName))
            markAllRead();
    }

    function markAllRead(): void {
        const ids = [];
        for (const entry of entries) {
            if (!entry.inCenter)
                continue;
            entry.unread = false;
            if (entry.notification)
                ids.push(entry.notification.id);
        }
        persisted.readIds = ids;
        touch();
    }

    function dismissEntry(entry: var): void {
        if (entry && entry.notification)
            entry.notification.dismiss();
    }

    function dismissAll(): void {
        const snapshot = entries.slice();
        for (const entry of snapshot) {
            if (entry.notification)
                entry.notification.dismiss();
        }
    }

    function defaultAction(entry: var): var {
        if (!entry || !entry.notification)
            return null;
        return entry.notification.actions.find(action => action.identifier === "default") || null;
    }

    function invokeDefault(entry: var): void {
        const action = defaultAction(entry);
        if (action)
            action.invoke();
        else
            dismissEntry(entry);
    }

    function invokeAction(action: var): void {
        if (action)
            action.invoke();
    }

    function buildGroups(source: var, popupOnly: bool): var {
        const groups = [];
        const byKey = {};
        for (const entry of source) {
            if (popupOnly && !entry.popupVisible)
                continue;
            const notification = entry.notification;
            if (!notification)
                continue;
            const key = `${entry.screenName}|${applicationKey(notification)}`;
            let group = byKey[key];
            if (!group) {
                group = {
                    "key": key,
                    "screenName": entry.screenName,
                    "appName": applicationName(notification),
                    "entries": [],
                    "latest": entry
                };
                byKey[key] = group;
                groups.push(group);
            }
            group.entries.push(entry);
        }
        return groups;
    }

    function popupGroupsForScreen(screenName: string): var {
        const ignored = revision;
        return buildGroups(entries, true)
            .filter(group => group.screenName === screenName)
            .slice(0, maxVisibleGroups);
    }

    PersistentProperties {
        id: persisted

        reloadableId: "bergNotificationSession"
        property bool dnd: false
        property var readIds: []
        onLoaded: root.restoreDndState()
    }

    FileView {
        id: dndStateFile

        path: root.dndStatePath
        preload: false
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                console.warn(`Notification state: unable to load ${path}: ${FileViewError.toString(error)}`);
        }
        onSaveFailed: error => {
            console.warn(`Notification state: unable to save ${path}: ${FileViewError.toString(error)}`);
        }
    }

    NotificationServer {
        id: server

        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: false
        bodyImagesSupported: false
        actionsSupported: true
        actionIconsSupported: false
        imageSupported: true
        inlineReplySupported: false
        extraHints: [
            "x-canonical-private-synchronous",
            "x-dunst-stack-tag"
        ]

        onNotification: notification => root.receiveNotification(notification)
    }

    readonly property Component entryComponent: Component {
        QtObject {
            id: entry

            property var notification: null
            property double receivedAt: 0
            property string screenName: ""
            property string stackKey: ""
            property int timeoutMs: 0
            property bool inCenter: true
            property bool unread: true
            property bool popupVisible: false

            function restartPopupTimer(): void {
                popupTimer.stop();
                if (popupVisible && timeoutMs > 0)
                    popupTimer.restart();
            }

            readonly property Timer popupTimer: Timer {
                interval: Math.max(1, entry.timeoutMs)
                repeat: false
                onTriggered: root.hidePopup(entry)
            }

            readonly property Connections notificationEvents: Connections {
                target: entry.notification

                function onClosed(reason): void {
                    root.removeEntry(entry);
                }

                function onExpireTimeoutChanged(): void {
                    root.refreshEntry(entry);
                    entry.restartPopupTimer();
                }

                function onUrgencyChanged(): void {
                    root.refreshEntry(entry);
                    entry.restartPopupTimer();
                }

                function onHintsChanged(): void {
                    root.refreshEntry(entry);
                }

                function onSummaryChanged(): void {
                    root.touch();
                }

                function onBodyChanged(): void {
                    root.touch();
                }

                function onActionsChanged(): void {
                    root.touch();
                }

                function onImageChanged(): void {
                    root.touch();
                }
            }
        }
    }

    readonly property Connections screenChanges: Connections {
        target: Quickshell

        function onScreensChanged(): void {
            root.rehomeMissingScreens();
        }
    }
}
