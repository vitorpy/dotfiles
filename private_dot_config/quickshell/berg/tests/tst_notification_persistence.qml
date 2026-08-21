import QtQuick
import QtTest
import "../NotificationPersistence.js" as NotificationPersistence

TestCase {
    name: "NotificationPersistence"

    function test_decodeDnd_data() {
        return [
            { tag: "empty uses enabled fallback", text: "", fallback: true, expected: true },
            { tag: "blank uses disabled fallback", text: "  \n", fallback: false, expected: false },
            { tag: "enabled state", text: '{"version":1,"dnd":true}', fallback: false, expected: true },
            { tag: "disabled state", text: '{"version":1,"dnd":false}', fallback: true, expected: false }
        ];
    }

    function test_decodeDnd(data) {
        compare(NotificationPersistence.decodeDnd(data.text, data.fallback), data.expected);
    }

    function decodeFails(text) {
        try {
            NotificationPersistence.decodeDnd(text, false);
            return false;
        } catch (error) {
            return true;
        }
    }

    function test_rejectsMalformedState() {
        verify(decodeFails("not json"));
        verify(decodeFails('{"version":1}'));
        verify(decodeFails('{"version":1,"dnd":"true"}'));
        verify(decodeFails('{"version":2,"dnd":true}'));
    }

    function test_encodeDnd() {
        compare(NotificationPersistence.encodeDnd(true), '{"version":1,"dnd":true}\n');
        compare(NotificationPersistence.encodeDnd(false), '{"version":1,"dnd":false}\n');
    }
}
