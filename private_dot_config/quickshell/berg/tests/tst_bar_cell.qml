import QtQuick
import QtTest
import "../components"

TestCase {
    id: testCase
    name: "BarCell"

    Item {
        id: testParent
        width: 240
        height: 80
    }

    Component {
        id: cellComponent

        BarCell {
            theme: ({
                "hoverLayer": "#33ffffff",
                "outlineVariant": "#44ffffff",
                "foreground": "#ffffff",
                "textFont": "sans-serif",
                "tooltipFontSize": 12,
                "tooltipSurface": "#202020"
            })
            interactive: true
            width: 100
            height: 54
        }
    }

    function test_defaultHoverGeometryMatchesCell() {
        const cell = createTemporaryObject(cellComponent, testParent);
        verify(cell !== null);

        const hover = findChild(cell, "hoverBackground");
        verify(hover !== null);
        compare(hover.x, 0);
        compare(hover.width, 100);
        compare(hover.radius, 8);
    }

    function test_hoverOverflowReachesRoundedPillEdges() {
        const cell = createTemporaryObject(cellComponent, testParent, {
            "hoverCornerRadius": 12,
            "hoverLeftOverflow": 8,
            "hoverRightOverflow": 8
        });
        verify(cell !== null);

        const hover = findChild(cell, "hoverBackground");
        verify(hover !== null);
        compare(hover.x, -8);
        compare(hover.width, 116);
        compare(hover.radius, 12);
    }

    function test_hoverOnlyCellDoesNotInterceptClicks() {
        const cell = createTemporaryObject(cellComponent, testParent, {
            "interactive": false,
            "hoverable": true
        });
        verify(cell !== null);

        const hoverTracker = findChild(cell, "hoverTracker");
        const interactionArea = findChild(cell, "interactionArea");
        verify(hoverTracker !== null);
        verify(interactionArea !== null);
        compare(hoverTracker.enabled, true);
        compare(interactionArea.enabled, false);
    }

    function test_tooltipKeepsHoverTrackingWithoutClickHandling() {
        const cell = createTemporaryObject(cellComponent, testParent, {
            "interactive": false,
            "hoverable": false,
            "tooltipText": "Battery status"
        });
        verify(cell !== null);

        const hoverTracker = findChild(cell, "hoverTracker");
        const interactionArea = findChild(cell, "interactionArea");
        verify(hoverTracker !== null);
        verify(interactionArea !== null);
        compare(hoverTracker.enabled, true);
        compare(interactionArea.enabled, false);
    }
}
