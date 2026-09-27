import QtQuick
import QtTest
import "../ClockDisplay.js" as ClockDisplay

TestCase {
    name: "ClockDisplay"

    function test_calendarUsesLocalCivilDateAcrossMidnight() {
        const civil = {year: 2026, month: 9, day: 26};
        const month = ClockDisplay.calendarMonth(civil, 0);
        compare(month.getUTCFullYear(), 2026);
        compare(month.getUTCMonth(), 8);
        let highlighted = 0;
        for (let index = 0; index < 42; index++) {
            const day = ClockDisplay.calendarCell(month, index);
            if (ClockDisplay.isToday(day, civil)) {
                compare(day.getUTCDate(), 26);
                highlighted++;
            }
        }
        compare(highlighted, 1);
        verify(!ClockDisplay.isToday(new Date(Date.UTC(2026, 8, 27)), civil));
    }

    function test_calendarMonthNavigationAndLeapDay() {
        const civil = {year: 2028, month: 2, day: 29};
        const previous = ClockDisplay.calendarMonth(civil, -2);
        compare(previous.getUTCFullYear(), 2027);
        compare(previous.getUTCMonth(), 11);
        compare(ClockDisplay.calendarMonth(civil, 11).getUTCFullYear(), 2029);
        verify(ClockDisplay.isToday(new Date(Date.UTC(2028, 1, 29)), civil));
    }

    function test_incompleteFormatterOutputRejected() {
        verify(!ClockDisplay.validSnapshot(null));
        verify(!ClockDisplay.validSnapshot({epoch: 1, local: {}, warsaw: {}}));
    }

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
