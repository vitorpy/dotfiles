import QtQuick
import QtTest
import "../OsdModel.js" as OsdModel

TestCase {
    name: "OsdModel"

    function test_progressState() {
        const state = OsdModel.stateForShow("volume", "", 75, 100, 800);
        compare(state.iconKey, "volume");
        compare(state.message, "75%");
        compare(state.value, 75);
        compare(state.maximum, 100);
        verify(state.hasProgress);
        compare(state.duration, 800);
    }

    function test_clampsProgressAndDuration() {
        const state = OsdModel.stateForShow("brightness", "Maximum", 180, 100, 90000);
        compare(state.message, "Maximum");
        compare(state.value, 100);
        compare(state.duration, 60000);
    }

    function test_messageState() {
        const state = OsdModel.stateForPayload('{"icon":"power","message":"Balanced"}');
        compare(state.iconKey, "power");
        compare(state.message, "Balanced");
        verify(!state.hasProgress);
        compare(state.duration, 1200);
    }

    function test_rejectsNonObjectPayload() {
        let failed = false;
        try {
            OsdModel.stateForPayload("[]");
        } catch (error) {
            failed = true;
        }
        verify(failed);
    }
}
