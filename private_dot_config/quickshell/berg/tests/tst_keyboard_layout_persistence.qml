import QtQuick
import QtTest
import "../KeyboardLayoutPersistence.js" as KeyboardLayoutPersistence

TestCase {
    name: "KeyboardLayoutPersistence"

    function test_normalizeLayout_data() {
        return [
            { tag: "Polish name", input: "Polish", expected: "PL" },
            { tag: "Polish code", input: "pl", expected: "PL" },
            { tag: "English international", input: "English (US, intl., with dead keys)", expected: "EN" },
            { tag: "US code", input: "us", expected: "EN" },
            { tag: "missing", input: "", expected: "?" }
        ];
    }

    function test_normalizeLayout(data) {
        compare(KeyboardLayoutPersistence.normalizeLayout(data.input), data.expected);
    }

    function test_layoutIds() {
        compare(KeyboardLayoutPersistence.layoutId("PL"), 0);
        compare(KeyboardLayoutPersistence.layoutId("EN"), 1);
        compare(KeyboardLayoutPersistence.layoutId("German"), -1);
    }

    function test_roundTrip_data() {
        return [
            { tag: "Polish", layout: "PL" },
            { tag: "English", layout: "EN" }
        ];
    }

    function test_roundTrip(data) {
        const serialized = KeyboardLayoutPersistence.encodeState(data.layout);
        const state = KeyboardLayoutPersistence.decodeState(serialized);
        compare(state.layout, data.layout);
        verify(!state.shouldSeed);
    }

    function test_missingStateSeedsCurrentLayout() {
        const state = KeyboardLayoutPersistence.decodeState("");
        compare(state.layout, "");
        verify(state.shouldSeed);
    }

    function decodeFails(text) {
        try {
            KeyboardLayoutPersistence.decodeState(text);
            return false;
        } catch (error) {
            return true;
        }
    }

    function test_rejectsMalformedState() {
        verify(decodeFails("not json"));
        verify(decodeFails('{"version":1}'));
        verify(decodeFails('{"version":2,"layout":"EN"}'));
        verify(decodeFails('{"version":1,"layout":"DE"}'));
    }
}
