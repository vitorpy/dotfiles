import QtQuick

QtObject {
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

    readonly property string textFont: "Avenir Next M for BBG"
    readonly property string symbolFont: ".SF Symbols Fallback"
    readonly property int fontSize: 16
    readonly property int tooltipFontSize: 14

    readonly property string speakerMuted: "􀊣"
    readonly property string speakerLow: "􀊥"
    readonly property string speakerHigh: "􀊧"
    readonly property string headphones: "􀑈"
    readonly property string microphone: "􀊱"
    readonly property string microphoneMuted: "􀊳"
    readonly property string brightness: "􀆮"
    readonly property var batteryLevels: ["􀛪", "􀛩", "􀺶", "􀺸", "􀛨"]
    readonly property string batteryCharging: "􀢋"
    readonly property string cpu: "􀧓"
    readonly property string temperature: "􀇬"
    readonly property string power: "􀆨"
    readonly property string dndEnabled: "􀋞"
    readonly property string dndDisabled: "􀋚"
    readonly property string updates: "􀁹"
    readonly property string reboot: "􀚂"
    readonly property string warning: "􀇿"
}
