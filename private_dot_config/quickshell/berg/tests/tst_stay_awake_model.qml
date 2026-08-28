import QtQuick
import QtTest
import "../StayAwakeModel.js" as StayAwakeModel

TestCase {
    name: "StayAwakeModel"

    function test_enableIsIdempotent() {
        verify(StayAwakeModel.nextEnabled(false, "enable"));
        verify(StayAwakeModel.nextEnabled(true, "enable"));
    }

    function test_disableIsIdempotent() {
        verify(!StayAwakeModel.nextEnabled(false, "disable"));
        verify(!StayAwakeModel.nextEnabled(true, "disable"));
    }

    function test_toggleInvertsState() {
        verify(StayAwakeModel.nextEnabled(false, "toggle"));
        verify(!StayAwakeModel.nextEnabled(true, "toggle"));
    }

    function test_rejectsUnknownAction() {
        let threw = false;
        try {
            StayAwakeModel.nextEnabled(false, "sleep");
        } catch (error) {
            threw = true;
        }
        verify(threw);
    }

    function test_statusDocumentsSessionScope() {
        const state = StayAwakeModel.status(true, true);
        verify(state.enabled);
        verify(state.loaded);
        compare(state.scope, "session");
        compare(state.mechanism, "wayland-idle-inhibit");
    }

    function test_sameSessionRestoresEnabledState() {
        const serialized = StayAwakeModel.encodeState(true, "session-a");
        const state = StayAwakeModel.decodeState(serialized, "session-a");

        verify(state.enabled);
        verify(!state.shouldSeed);
    }

    function test_newSessionResetsAndSeedsDisabledState() {
        const serialized = StayAwakeModel.encodeState(true, "session-a");
        const state = StayAwakeModel.decodeState(serialized, "session-b");

        verify(!state.enabled);
        verify(state.shouldSeed);
    }

    function test_missingStateSeedsDisabledState() {
        const state = StayAwakeModel.decodeState("", "session-a");

        verify(!state.enabled);
        verify(state.shouldSeed);
    }

    function test_rejectsMalformedState() {
        let threw = false;
        try {
            StayAwakeModel.decodeState('{"version":1}', "session-a");
        } catch (error) {
            threw = true;
        }
        verify(threw);
    }
}
