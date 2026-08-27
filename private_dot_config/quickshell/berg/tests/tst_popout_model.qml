import QtQuick
import QtTest
import "../PopoutModel.js" as PopoutModel

TestCase {
    name: "PopoutModel"

    function test_openUsesRequestedScreen() {
        const state = PopoutModel.openState("clock", "eDP-1", "DP-3");
        compare(state.activePanel, "clock");
        compare(state.screenName, "eDP-1");
    }

    function test_openFallsBackToFocusedScreen() {
        const state = PopoutModel.openState("notifications", "", "DP-3");
        compare(state.activePanel, "notifications");
        compare(state.screenName, "DP-3");
    }

    function test_toggleClosesSameTarget() {
        const state = PopoutModel.toggleState("clock", "eDP-1", "clock", "eDP-1", "DP-3");
        compare(state.activePanel, "");
        compare(state.screenName, "");
    }

    function test_toggleSwitchesPanelAtomically() {
        const state = PopoutModel.toggleState("clock", "eDP-1", "notifications", "eDP-1", "DP-3");
        compare(state.activePanel, "notifications");
        compare(state.screenName, "eDP-1");
    }
}
