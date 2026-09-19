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

    function test_hoverRevealIsCollapsedAtRest() {
        compare(BarLayout.hoverRevealWidth(false, 100), 0);
    }

    function test_hoverRevealUsesContentWidthWhileHovered() {
        compare(BarLayout.hoverRevealWidth(true, 100), 100);
    }

    function test_hoverRevealRejectsInvalidWidths() {
        compare(BarLayout.hoverRevealWidth(true, -1), 0);
        compare(BarLayout.hoverRevealWidth(true, Number.NaN), 0);
    }
}
