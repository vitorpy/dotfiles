import QtQuick
import QtTest
import "../PackageUpdates.js" as PackageUpdates

TestCase {
    name: "PackageUpdates"

    function test_periodicRefreshInterval() {
        compare(PackageUpdates.periodicRefreshIntervalMs(), 3600000);
    }

    function test_launchCommand() {
        compare(
            PackageUpdates.launchCommand("/home/example"),
            [
                "/usr/bin/ghostty",
                "-e",
                "/home/example/.config/arch/update-system.sh"
            ]
        );
    }

    function test_deduplicateRpmRepositories() {
        compare(PackageUpdates.packageCount("foo.x86_64\nfoo.x86_64\nfoo.i686\n", "fedora"), 2);
        compare(PackageUpdates.packageCount("foo\nbar\n", "arch"), 2);
    }

    function test_backends() {
        compare(PackageUpdates.backendFromOsRelease('NAME="Arch Linux"\nID=arch\n'), "arch");
        compare(PackageUpdates.backendFromOsRelease('ID="fedora"\nVERSION_ID=44\n'), "fedora");
        compare(PackageUpdates.backendFromOsRelease('ID=debian\n'), "unsupported");
        compare(PackageUpdates.backendFromOsRelease(''), "unsupported");
        compare(PackageUpdates.launchCommand("/home/example", "fedora")[2], "/home/example/.config/fedora/update-system.sh");
        compare(PackageUpdates.officialCommand("arch"), ["/usr/bin/checkupdates"]);
        verify(PackageUpdates.officialCommand("fedora").indexOf("--upgrades") >= 0);
    }

    function test_lineCount_data() {
        return [
            { tag: "empty", output: "", expected: 0 },
            { tag: "whitespace", output: "  \n\t", expected: 0 },
            { tag: "one package", output: "linux 6.11 -> 6.12", expected: 1 },
            {
                tag: "blank lines ignored",
                output: "linux 6.11 -> 6.12\n\nmesa 1 -> 2\n",
                expected: 2
            }
        ];
    }

    function test_lineCount(data) {
        compare(PackageUpdates.lineCount(data.output), data.expected);
    }

    function test_refreshIsBusy_data() {
        return [
            { tag: "idle", officialRunning: false, aurRunning: false, expected: false },
            { tag: "official", officialRunning: true, aurRunning: false, expected: true },
            { tag: "AUR", officialRunning: false, aurRunning: true, expected: true },
            { tag: "both", officialRunning: true, aurRunning: true, expected: true }
        ];
    }

    function test_refreshIsBusy(data) {
        compare(
            PackageUpdates.refreshIsBusy(data.officialRunning, data.aurRunning),
            data.expected
        );
    }
}
