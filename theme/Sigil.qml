import QtQuick
Item {
    id: sigil
    property bool motionEnabled: true
    property color ink: "#9e8bb5"
    Rectangle { anchors.fill: parent; radius: width/2; color: "transparent"; border.color: "#d2c7dd" }
    Item {
        anchors.fill: parent
        RotationAnimation on rotation { from: 0; to: 360; duration: 90000; running: sigil.motionEnabled; loops: Animation.Infinite }
        Repeater {
            model: 8
            Rectangle {
                required property int index
                width: 4; height: 4; color: sigil.ink; rotation: 45
                x: sigil.width/2 + Math.cos(index*Math.PI/4)*(sigil.width/2)-2
                y: sigil.height/2 + Math.sin(index*Math.PI/4)*(sigil.height/2)-2
            }
        }
    }
    Image { anchors.fill: parent; anchors.margins: parent.width*0.14; source: "assets/compass.svg"; opacity: .9 }
}
