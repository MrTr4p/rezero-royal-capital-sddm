import QtQuick
Item {
    id: seal
    property real seconds: 0
    property real strength: 1
    property bool rewinding: false
    Item {
        anchors.fill: parent; rotation: -seal.seconds*2; opacity: .28*seal.strength
        Canvas {
            anchors.fill: parent
            onPaint: {
                var c=getContext("2d"), mid=width/2, r=width*.47;
                c.clearRect(0,0,width,height); c.strokeStyle="#8e75ad"; c.lineWidth=1.4;
                c.beginPath(); c.arc(mid,mid,r,0,Math.PI*2); c.stroke();
                c.beginPath(); c.arc(mid,mid,r-16,0,Math.PI*2); c.stroke();
                for(var i=0;i<60;i++) {
                    var a=i*Math.PI/30, length=i%5===0?21:7;
                    c.beginPath(); c.moveTo(mid+Math.sin(a)*(r-24),mid-Math.cos(a)*(r-24));
                    c.lineTo(mid+Math.sin(a)*(r-24-length),mid-Math.cos(a)*(r-24-length)); c.stroke();
                }
                var numerals=["XII","I","II","III","IV","V","VI","VII","VIII","IX","X","XI"];
                c.font="20px serif"; c.fillStyle="#806394"; c.textAlign="center"; c.textBaseline="middle";
                for(var j=0;j<12;j++) { var a=j*Math.PI/6; c.fillText(numerals[j],mid+Math.sin(a)*(r-67),mid-Math.cos(a)*(r-67)); }
            }
        }
    }
    Item {
        anchors.fill: parent; rotation: seal.seconds*3.4; opacity: .22*seal.strength
        Canvas {
            anchors.fill: parent
            onPaint: {
                var c=getContext("2d"), mid=width/2, r=width*.36; c.strokeStyle="#a38bbb"; c.lineWidth=1.1;
                for(var i=0;i<4;i++) { c.beginPath(); c.arc(mid,mid,r,i*Math.PI/2+.13,(i+1)*Math.PI/2-.13); c.stroke(); }
                for(var j=0;j<4;j++) {
                    var a=j*Math.PI/2, x=mid+Math.cos(a)*r, y=mid+Math.sin(a)*r;
                    c.beginPath(); c.moveTo(x,y-8); c.lineTo(x+5,y); c.lineTo(x,y+8); c.lineTo(x-5,y); c.closePath(); c.stroke();
                }
            }
        }
    }
    Rectangle {
        anchors.centerIn: parent; width: parent.width*.96; height: width; radius: width/2
        color: "transparent"; border.width: seal.rewinding ? 3 : 1; border.color: "#b499ce"
        opacity: (seal.rewinding ? .60 : .14 + .07*Math.sin(seal.seconds))*seal.strength
        scale: 1+.012*Math.sin(seal.seconds*1.7)
    }
}
