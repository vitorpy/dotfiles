import QtQuick
import QtTest
import "../AttentionHysteresis.js" as AttentionHysteresis

TestCase {
    name: "AttentionHysteresis"

    function test_cpuActivationAndRecovery() {
        let visible = AttentionHysteresis.highValueVisible(70, false, 70, 60);
        verify(!visible);

        visible = AttentionHysteresis.highValueVisible(71, visible, 70, 60);
        verify(visible);

        visible = AttentionHysteresis.highValueVisible(65, visible, 70, 60);
        verify(visible);

        visible = AttentionHysteresis.highValueVisible(60, visible, 70, 60);
        verify(!visible);
    }

    function test_temperatureActivationAndRecovery() {
        let visible = AttentionHysteresis.highValueVisible(55, false, 55, 50);
        verify(!visible);

        visible = AttentionHysteresis.highValueVisible(56, visible, 55, 50);
        verify(visible);

        visible = AttentionHysteresis.highValueVisible(52, visible, 55, 50);
        verify(visible);

        visible = AttentionHysteresis.highValueVisible(50, visible, 55, 50);
        verify(!visible);
    }

    function test_initialReadingInsideBandRemainsHidden() {
        verify(!AttentionHysteresis.highValueVisible(65, false, 70, 60));
        verify(!AttentionHysteresis.highValueVisible(52, false, 55, 50));
    }

    function test_invalidInputPreservesVisibility() {
        verify(AttentionHysteresis.highValueVisible("invalid", true, 70, 60));
        verify(!AttentionHysteresis.highValueVisible(75, false, 60, 70));
    }
}
