import QtQuick
Item {
    id: background
    property url source
    property bool motionEnabled: true
    property bool hairSwayEnabled: false
    property int sceneMode: 0
    property real motionStrength: 1
    property real pointerX: 0
    property real pointerY: 0
    property bool busy: false
    property real elapsedMs: 0
    property bool rewinding: false
    readonly property real seconds: elapsedMs / 1000
    property real driftX: motionEnabled ? pointerX*12*motionStrength : 0
    property real driftY: motionEnabled ? pointerY*7*motionStrength : 0
    clip: true
    Behavior on driftX { NumberAnimation { duration: 1300; easing.type: Easing.OutCubic } }
    Behavior on driftY { NumberAnimation { duration: 1300; easing.type: Easing.OutCubic } }
    function rewind() { if(motionEnabled && sceneMode===2) { rewinding=true; rewindTimer.restart(); } }
    Timer { id: rewindTimer; interval: 1600; onTriggered: background.rewinding=false }
    onMotionEnabledChanged: if(!motionEnabled) { rewinding=false; rewindTimer.stop(); }
    Timer {
        id: motionClock; objectName: "motionClock"
        property real lastTick: Date.now()
        interval: 40; repeat: true; running: background.motionEnabled && background.visible
        onRunningChanged: lastTick=Date.now()
        onTriggered: {
            var current=Date.now(), delta=Math.min(80,current-lastTick); lastTick=current;
            background.elapsedMs += delta * (background.rewinding ? -6 : background.busy ? 2 : 1) * background.motionStrength;
        }
    }
    WindArtwork {
        id: artwork; objectName: "backgroundArtwork"
        x: -width*.018+background.driftX + (background.motionEnabled ? Math.sin(background.seconds*.14)*7*background.motionStrength : 0)
        y: -height*.018+background.driftY
        width: parent.width*1.036; height: parent.height*1.036
        scale: background.motionEnabled ? 1+Math.sin(background.seconds*.19)*.005*background.motionStrength : 1
        source: background.source; motionEnabled: background.motionEnabled
        hairSwayEnabled: background.hairSwayEnabled
        sceneMode: background.sceneMode; windStrength: background.motionStrength
        elapsedMs: background.elapsedMs; opacity: .91
    }
    Rectangle { anchors.fill: parent; color: "#0bf6f3eb" }
    ClockSeal {
        objectName: "clockSeal"
        x: background.width*.45+background.driftX*.4; y: -background.height*.015+background.driftY*.4
        width: background.height*.91; height: width
        visible: background.sceneMode===2
        seconds: background.seconds; strength: background.motionEnabled ? 1 : .7
        rewinding: background.rewinding
    }
    // Independent translucent mist layers drift across the lower illustration.
    Repeater {
        model: background.sceneMode>0 ? 3 : 1
        Canvas {
            required property int index
            width: background.width*.72; height: background.height*.23
            x: background.width*.29+Math.sin(background.seconds*.12+index*2)*135*background.motionStrength
            y: background.height*(.64+index*.09)
            opacity: background.sceneMode===2 ? .38 : .28
            onPaint: {
                var c=getContext("2d"); c.scale(1,height/width);
                var g=c.createRadialGradient(width/2,width/2,0,width/2,width/2,width/2);
                g.addColorStop(0,"rgba(253,251,245,.9)");g.addColorStop(.5,"rgba(248,245,239,.5)");g.addColorStop(1,"rgba(248,245,239,0)");
                c.fillStyle=g; c.fillRect(0,0,width,width);
            }
        }
    }
    Repeater {
        model: background.motionEnabled ? (background.sceneMode>0 ? 28 : 14) : 0
        Item {
            id: particle
            required property int index
            readonly property real phase: background.elapsedMs/(17000+(index%7)*1700)+index/28
            readonly property real journey: ((phase%1)+1)%1
            readonly property real depth: .6+(index%4)*.25
            width: (background.sceneMode===2 ? 8 : 24+(index%4)*9)*depth
            height: background.sceneMode===2 ? width : width*.52
            x: background.width*.30 + (index*151%(background.width*.70)) + Math.sin(journey*7+index)*140
            y: background.sceneMode===1 ? -90+journey*(background.height+180) : background.height+70-journey*(background.height+150)
            rotation: background.seconds*(index%2===0 ? 15 : -11)+index*29
            opacity: Math.sin(journey*Math.PI)*(.26+depth*.13)
            scale: 1+Math.sin(background.seconds*1.4+index)*.15
            Image { anchors.fill: parent; visible: background.sceneMode!==2; source: background.sceneMode===1 ? "assets/petal.svg" : "assets/feather.svg" }
            Rectangle { anchors.fill: parent; visible: background.sceneMode===2; color: index%3===0 ? "#83649e" : "#bca2ce"; rotation: 45; radius: index%2 }
        }
    }
}
