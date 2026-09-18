import QtQuick
import QtTest
import "../BarLayout.js" as BarLayout

TestCase {
    name: "BarLayout"

    function test_clockRemainsCenteredWithEnoughSpace() {
        compare(BarLayout.collisionAwareX(1920, 300, 200, 1500), 810);
    }

    function test_clockShiftsLeftBeforeRightGroup() {
        compare(BarLayout.collisionAwareX(1920, 400, 200, 1100), 700);
    }

    function test_clockStaysClearOfLeftGroup() {
        compare(BarLayout.collisionAwareX(800, 200, 350, 700), 350);
    }

    function test_rightBoundaryWinsWhenGapIsTooNarrow() {
        compare(BarLayout.collisionAwareX(800, 300, 220, 480), 180);
    }
}
