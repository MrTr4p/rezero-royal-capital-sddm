import QtQuick
import QtQuick.Controls
Button {
    id: control
    property bool primary: false
    property bool quiet: false
    property string glyph: ""
    property string trailing: ""
    implicitWidth: 180; implicitHeight: 54
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : 0.4
    Accessible.name: text
    background: Rectangle {
        radius: 3
        color: control.primary ? (control.down ? "#514370" : control.hovered ? "#65558f" : "#71639e") : control.hovered ? "#e9e2ed" : "transparent"
        border.width: control.quiet && !control.activeFocus ? 0 : 1
        border.color: control.activeFocus ? "#514370" : control.primary ? "#71639e" : "#d4cbdc"
        Behavior on color { ColorAnimation { duration: 140 } }
    }
    contentItem: Item {
        UiText { anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter; text: control.glyph; font.pixelSize: 21; color: control.primary ? "#fcf9f4" : "#71639e" }
        UiText { anchors.centerIn: parent; text: control.text; font.pixelSize: 15; font.letterSpacing: control.primary ? 1.5 : 0.2; color: control.primary ? "#fcf9f4" : "#59526d" }
        UiText { anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; text: control.trailing; font.pixelSize: 24; color: control.primary ? "#fcf9f4" : "#71639e" }
    }
}
