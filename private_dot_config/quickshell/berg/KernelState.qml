import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property string runningKernel: ""
    property string latestInstalledKernel: ""
    property bool rebootRequired: false
    property bool hasValue: false
    property string health: "loading"
    property string lastError: ""
    property var lastSuccess: null
    property bool moduleCheckDone: false
    property bool moduleDirectoryExists: true
    property bool moduleListDone: false

    readonly property bool visible: rebootRequired || health === "stale" || health === "error"
    readonly property string tooltip: {
        if (lastError)
            return `Reboot status unavailable\n${lastError}`;
        return rebootRequired
            ? `Reboot required: kernel ${runningKernel} → ${latestInstalledKernel || "unknown"}`
            : "Running kernel modules are installed";
    }

    function versionTokens(value: string): var {
        return value.match(/[0-9]+|[^0-9]+/g) || [value];
    }

    function compareVersions(left: string, right: string): int {
        const a = versionTokens(left);
        const b = versionTokens(right);
        const length = Math.max(a.length, b.length);
        for (let index = 0; index < length; ++index) {
            if (index >= a.length)
                return -1;
            if (index >= b.length)
                return 1;
            const aNumber = /^[0-9]+$/.test(a[index]);
            const bNumber = /^[0-9]+$/.test(b[index]);
            if (aNumber && bNumber) {
                const difference = Number(a[index]) - Number(b[index]);
                if (difference !== 0)
                    return difference;
            } else if (a[index] !== b[index]) {
                return a[index] < b[index] ? -1 : 1;
            }
        }
        return 0;
    }

    function fail(message: string): void {
        lastError = message;
        health = hasValue ? "stale" : "error";
        console.warn(`Kernel state: ${message}`);
    }

    function consumeKernel(text: string): void {
        const value = text.trim();
        if (!value) {
            fail("/proc/sys/kernel/osrelease was empty");
            return;
        }

        runningKernel = value;
        moduleCheckDone = false;
        moduleListDone = false;
        moduleCheck.command = ["/usr/bin/test", "-d", `/usr/lib/modules/${runningKernel}`];
        moduleCheck.refresh();
        moduleList.refresh();
    }

    function consumeModules(text: string): void {
        const versions = text.split(/\r?\n/).map(value => value.trim()).filter(value => value.length > 0);
        versions.sort((left, right) => compareVersions(left, right));
        latestInstalledKernel = versions.length > 0 ? versions[versions.length - 1] : "";
        moduleListDone = true;
        finalizeIfReady();
    }

    function finalizeIfReady(): void {
        if (!moduleCheckDone || !moduleListDone)
            return;
        rebootRequired = !moduleDirectoryExists;
        hasValue = true;
        health = "ready";
        lastError = "";
        lastSuccess = new Date();
    }

    function refresh(): void {
        kernelFile.reload();
    }

    readonly property FileView kernelFile: FileView {
        id: kernelFile

        path: "/proc/sys/kernel/osrelease"
        printErrors: false
        onLoaded: root.consumeKernel(text())
        onLoadFailed: error => root.fail(`Unable to read the running kernel: ${FileViewError.toString(error)}`)
    }

    readonly property ProcessJob moduleCheck: ProcessJob {
        runOnStart: false
        acceptedExitCodes: [0, 1]
        timeoutMs: 3000
        onSucceeded: (exitCode, output, errorOutput) => {
            root.moduleDirectoryExists = exitCode === 0;
            root.moduleCheckDone = true;
            root.finalizeIfReady();
        }
        onFailed: (message, exitCode, output, errorOutput) => root.fail(`Unable to inspect running kernel modules: ${message}`)
    }

    readonly property ProcessJob moduleList: ProcessJob {
        command: ["/usr/bin/find", "/usr/lib/modules", "-mindepth", "1", "-maxdepth", "1", "-type", "d", "-printf", "%f\\n"]
        runOnStart: false
        timeoutMs: 3000
        onSucceeded: (exitCode, output, errorOutput) => root.consumeModules(output)
        onFailed: (message, exitCode, output, errorOutput) => root.fail(`Unable to list installed kernels: ${message}`)
    }

    readonly property Timer refreshTimer: Timer {
        interval: 300000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
