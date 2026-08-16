import QtQuick

Row {
    id: root

    required property var theme
    property string glyph: ""
    property string label: ""
    property color foreground: theme.foreground
    property bool glyphAfter: false
    property bool warning: false
    property int gap: (Number(Boolean(label)) + Number(Boolean(glyph)) + Number(warning)) > 1 ? 6 : 0

    spacing: gap

    Text {
        visible: root.glyph && !root.glyphAfter
        text: root.glyph
        color: root.foreground
        font.family: root.theme.symbolFont
        font.pixelSize: root.theme.fontSize
        font.weight: Font.Medium
        verticalAlignment: Text.AlignVCenter
    }

    Text {
        visible: root.label
        text: root.label
        color: root.foreground
        font.family: root.theme.textFont
        font.pixelSize: root.theme.fontSize
        font.weight: Font.Medium
        verticalAlignment: Text.AlignVCenter
    }

    Text {
        visible: root.glyph && root.glyphAfter
        text: root.glyph
        color: root.foreground
        font.family: root.theme.symbolFont
        font.pixelSize: root.theme.fontSize
        font.weight: Font.Medium
        verticalAlignment: Text.AlignVCenter
    }

    Text {
        visible: root.warning
        text: root.theme.warning
        color: root.theme.error
        font.family: root.theme.symbolFont
        font.pixelSize: root.theme.fontSize
        font.weight: Font.Medium
        verticalAlignment: Text.AlignVCenter
    }
}
