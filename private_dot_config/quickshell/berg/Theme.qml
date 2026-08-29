import QtQuick

SfSymbols {
    readonly property color surface: "#000000"
    readonly property color surfaceContainer: "#202020"
    readonly property color surfaceContainerHigh: "#282828"
    readonly property color foreground: "#d7d7d7"
    readonly property color foregroundMuted: "#acacae"
    readonly property color outline: "#646667"
    readonly property color outlineVariant: "#464646"
    readonly property color primary: "#f49f31"
    readonly property color error: "#d54135"
    readonly property color onErrorColor: "#000000"
    readonly property color hoverLayer: "#14f49f31"
    readonly property color tooltipSurface: "#f0000000"
    readonly property color accountAccent1: primary
    readonly property color accountAccent2: foregroundMuted
    readonly property color accountAccent3: outline
    readonly property color accountAccent4: foreground

    function gmailAccountColor(index: int): color {
        switch (index % 4) {
        case 0:
            return accountAccent1;
        case 1:
            return accountAccent2;
        case 2:
            return accountAccent3;
        default:
            return accountAccent4;
        }
    }

    readonly property string textFont: "Avenir Next M for BBG"
    readonly property string symbolFont: ".SF Symbols Fallback"
    readonly property int fontSize: 16
    readonly property int tooltipFontSize: 14
}
