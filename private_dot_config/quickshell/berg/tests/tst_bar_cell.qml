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
}
