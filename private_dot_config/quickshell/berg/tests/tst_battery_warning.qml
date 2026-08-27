import QtQuick
import QtTest
import "../BatteryWarning.js" as BatteryWarning

TestCase {
    name: "BatteryWarning"

    function test_warnsOnceAtThreshold() {
        const first = BatteryWarning.evaluate(0.10, true, true, true, false, 10, 15);
        compare(first.percentage, 10);
        verify(first.notify);
        verify(first.notified);

        const second = BatteryWarning.evaluate(9, true, true, true, first.notified, 10, 15);
        verify(!second.notify);
        verify(second.notified);
    }

    function test_hysteresisPreventsThresholdJitter() {
        const jitter = BatteryWarning.evaluate(12, true, true, true, true, 10, 15);
        verify(!jitter.notify);
        verify(jitter.notified);

        const reset = BatteryWarning.evaluate(15, true, true, true, true, 10, 15);
        verify(!reset.notify);
        verify(!reset.notified);
    }

    function test_externalPowerResetsWarning() {
        const state = BatteryWarning.evaluate(8, true, false, false, true, 10, 15);
        verify(!state.notify);
        verify(!state.notified);
    }

    function test_unavailableBatteryPreservesState() {
        const state = BatteryWarning.evaluate(-1, false, true, true, true, 10, 15);
        verify(!state.notify);
        verify(state.notified);
    }
}
