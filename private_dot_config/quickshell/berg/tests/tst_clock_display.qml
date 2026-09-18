import QtQuick
import QtTest
import "../ClockDisplay.js" as ClockDisplay

TestCase {
    name: "ClockDisplay"

    function test_sameDateOmitsWarsawDate() {
        compare(ClockDisplay.warsawLabel("18.09", "18.09 22:32"), "Warsaw 22:32");
    }

    function test_differentDateShowsWarsawDate() {
        compare(ClockDisplay.warsawLabel("19.09", "18.09 23:32"), "Warsaw 18.09 23:32");
    }

    function test_yearBoundaryShowsWarsawDate() {
        compare(ClockDisplay.warsawLabel("01.01", "31.12 23:32"), "Warsaw 31.12 23:32");
    }
}
