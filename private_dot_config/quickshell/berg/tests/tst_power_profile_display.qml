import QtQuick
import QtTest
import "../PowerProfileDisplay.js" as PowerProfileDisplay

TestCase {
    name: "PowerProfileDisplay"

    function monitor(name, width, height, refreshRate, modes, extra) {
        return Object.assign({
            name: name,
            width: width,
            height: height,
            refreshRate: refreshRate,
            availableModes: modes,
            x: 0,
            y: 0,
            scale: 1,
            disabled: false
        }, extra || {});
    }

    function serialized(monitors) {
        return JSON.stringify(monitors);
    }

    function test_discoversFramework13NativeResolution() {
        const result = PowerProfileDisplay.policy(serialized([
            monitor("eDP-1", 2256, 1504, 60, ["2256x1504@60.00Hz"])
        ]), 48);

        verify(result.applicable);
        compare(result.targetMode, "2256x1504@48");
        compare(result.fallbackMode, "2256x1504@60");
    }

    function test_discoversFramework12NativeResolution() {
        const result = PowerProfileDisplay.policy(serialized([
            monitor("eDP-1", 2256, 1504, 48, ["1920x1200@60.00Hz"])
        ]), 48);

        compare(result.targetMode, "1920x1200@48");
        compare(result.fallbackMode, "1920x1200@60");
    }

    function test_ignoresExternalAndDisabledPanels() {
        const result = PowerProfileDisplay.policy(serialized([
            monitor("DP-3", 3840, 2160, 60, ["3840x2160@60.00Hz"]),
            monitor("eDP-1", 2256, 1504, 60, ["2256x1504@60.00Hz"], { disabled: true }),
            monitor("eDP-2", 1920, 1200, 60, ["1920x1200@60.00Hz"])
        ]), 60);

        compare(result.output, "eDP-2");
        compare(result.targetMode, "1920x1200@60");
    }

    function test_selectsLargestResolutionAndClosestFallback() {
        const result = PowerProfileDisplay.policy(serialized([
            monitor("eDP-1", 1920, 1080, 60, [
                "1280x720@120.00Hz",
                "1920x1080@60.00Hz",
                "1920x1080@50.00Hz",
                "not-a-mode"
            ], { x: 1920, y: -40, scale: 1.25 })
        ]), 48);

        compare(result.width, 1920);
        compare(result.height, 1080);
        compare(result.fallbackRefreshRate, 50);
        compare(result.position, "1920x-40");
        compare(result.scale, 1.25);
    }

    function test_noInternalPanelIsNotApplicable() {
        const result = PowerProfileDisplay.policy(serialized([
            monitor("DP-1", 2560, 1440, 60, ["2560x1440@60.00Hz"])
        ]), 48);
        verify(!result.applicable);
    }

    function test_rejectsInvalidPayloadAndMissingModes() {
        let invalidPayloadRejected = false;
        try {
            PowerProfileDisplay.policy("{}", 48);
        } catch (error) {
            invalidPayloadRejected = true;
        }
        verify(invalidPayloadRejected);

        let missingModesRejected = false;
        try {
            PowerProfileDisplay.policy(serialized([
                monitor("eDP-1", 1920, 1200, 60, ["invalid"])
            ]), 48);
        } catch (error) {
            missingModesRejected = true;
        }
        verify(missingModesRejected);
    }

    function test_buildsEscapedMonitorExpression() {
        const result = PowerProfileDisplay.policy(serialized([
            monitor("eDP-1", 1920, 1200, 60, ["1920x1200@60.00Hz"], { x: 10, y: 20 })
        ]), 48);
        compare(
            PowerProfileDisplay.monitorExpression(result, result.targetMode),
            'hl.monitor({ output = "eDP-1", mode = "1920x1200@48", position = "10x20", scale = 1 })'
        );
    }

    function test_verifiesDimensionsAndRefreshRate() {
        const result = PowerProfileDisplay.policy(serialized([
            monitor("eDP-1", 2256, 1504, 60, ["1920x1200@60.00Hz"])
        ]), 48);
        verify(PowerProfileDisplay.verifies(serialized([
            monitor("eDP-1", 1920, 1200, 48.00001, ["1920x1200@60.00Hz"])
        ]), result, 48));
        verify(!PowerProfileDisplay.verifies(serialized([
            monitor("eDP-1", 2256, 1504, 48, ["1920x1200@60.00Hz"])
        ]), result, 48));
        verify(!PowerProfileDisplay.verifies(serialized([
            monitor("eDP-1", 1920, 1200, 60, ["1920x1200@60.00Hz"])
        ]), result, 48));
    }
}
