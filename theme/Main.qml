import QtQuick
import QtQuick.Controls

Rectangle {
    id: root
    width: 1920; height: 1080; color: "#f2efe7"
    readonly property color ink: "#30344f"
    readonly property color accent: "#71639e"
    readonly property bool preview: typeof previewMode !== "undefined" && previewMode
    readonly property bool animations: config.stringValue("Animations") !== "false" && config.stringValue("MotionLevel") !== "still"
    readonly property real motionStrength: config.stringValue("MotionLevel") === "gentle" ? .35 : 1
    readonly property string host: sddm.hostName || "localhost"
    readonly property string backgroundPath: config.stringValue("Background") || "assets/background.png"
    readonly property int sceneMode: backgroundPath.indexOf("subaru-promise")>=0 ? 1 : backgroundPath.indexOf("subaru-rewind")>=0 ? 2 : 0
    readonly property string sceneTitle: sceneMode===1 ? "A Promise at Dawn" : sceneMode===2 ? "Return by Death" : backgroundPath.indexOf("royal-capital")>=0 ? "Royal Capital" : backgroundPath.indexOf("moonlit-forest")>=0 ? "Moonlit Forest" : "Sanctuary"
    readonly property real sceneScale: Math.min(width/1920, height/1080)
    property var now: new Date()
    property bool busy: false
    property bool failed: false
    property bool signedIn: false
    property bool revealPassword: false
    property bool entered: false
    property string message: ""
    property string powerAction: ""
    property int sessionIndex: -1
    property string sessionName: "No session available"
    property alias userInput: username
    property alias passwordInput: password

    FontLoader { source: "assets/EBGaramond.ttf" }
    FontLoader { source: "assets/NotoSans-Regular.ttf" }
    FontLoader { source: "assets/NotoSansMono-Regular.ttf" }

    function chooseSession() {
        if (!sessions.count) { sessionIndex = -1; sessionName = "No session available"; return; }
        var choice = Math.max(0, Math.min(sessions.count-1, sessionModel.lastIndex));
        for (var i=0; i<sessions.count; i++) if (sessions.itemAt(i).sessionFile === config.stringValue("PreferredSession")) choice = i;
        selectSession(choice);
    }
    function selectSession(index) {
        sessionIndex = index;
        sessionName = sessions.itemAt(index).sessionLabel;
        sessionMenu.close();
    }
    function submit() {
        if (busy) return;
        failed = false; signedIn = false;
        if (!username.text.trim()) { failed = true; message = "Enter your username to continue."; username.forceActiveFocus(); return; }
        if (sessionIndex < 0) { failed = true; message = "No desktop session is available."; return; }
        if (!password.text.length) { failed = true; message = "Enter your password to continue."; password.forceActiveFocus(); return; }
        busy = true; revealPassword = false; message = "Opening the next chapter…";
        sddm.login(username.text.trim(), password.text, sessionIndex);
    }
    function requestPower(action) {
        powerAction = action; powerDialog.open();
    }
    function confirmPowerAction() {
        if (powerAction === "Power off" && sddm.canPowerOff) sddm.powerOff();
        else if (powerAction === "Restart" && sddm.canReboot) sddm.reboot();
        else if (powerAction === "Sleep" && sddm.canSuspend) sddm.suspend();
        powerDialog.close();
        if (preview) { message = powerAction + " preview complete."; noticeTimer.restart(); }
    }
    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.now = new Date() }
    Timer { id: noticeTimer; interval: 3000; onTriggered: root.message = "" }
    Timer { id: resetDemo; interval: 2800; onTriggered: { root.busy = false; root.signedIn = false; root.message = ""; password.forceActiveFocus(); } }
    Connections { target: sessionModel; function onModelReset() { Qt.callLater(root.chooseSession); } }
    Connections {
        target: sddm
        function onLoginFailed() {
            root.busy = false; root.failed = true; root.revealPassword = false;
            root.message = root.sceneMode===2 ? "The loop begins again. Try your password once more." : "A wrong turn. Take a breath and try again.";
            password.clear(); password.forceActiveFocus();
            animatedScene.rewind();
            if (root.animations) failurePulse.restart();
        }
        function onLoginSucceeded() {
            password.clear(); root.signedIn = true;
            root.message = "Your next chapter awaits.";
            if (root.preview) resetDemo.restart();
        }
    }
    Component.onCompleted: { Qt.callLater(chooseSession); entered = true; password.forceActiveFocus(); }

    Item {
        id: scene
        width: 1920; height: 1080; anchors.centerIn: parent; scale: root.sceneScale
        AnimatedBackground {
            id: animatedScene; objectName: "animatedScene"
            anchors.fill: parent; source: root.backgroundPath
            motionEnabled: root.animations
            hairSwayEnabled: root.sceneMode>0 || config.stringValue("HairSway") === "true"
            sceneMode: root.sceneMode; motionStrength: root.motionStrength; busy: root.busy
            pointerX: sceneHover.hovered ? (sceneHover.point.position.x/scene.width-.5)*2 : 0
            pointerY: sceneHover.hovered ? (sceneHover.point.position.y/scene.height-.5)*2 : 0
        }
        HoverHandler { id: sceneHover; enabled: root.animations }
        Rectangle { x: 0; y: 0; width: 1920; height: 98; color: "#9af2efe7" }
        Rectangle { x: 40; y: 39; width: 1840; height: 1002; color: "transparent"; border.color: "#70b9acc7"; border.width: 1 }
        Repeater {
            model: 4
            UiText { required property int index; x: index%2 === 0 ? 31 : 1871; y: index<2 ? 24 : 1025; text: "+"; color: "#9a88af"; font.family: "Noto Sans Mono"; font.pixelSize: 23 }
        }

        // An understated header belongs to the native scene, not the browser shell.
        Row {
            x: 84; y: 64; spacing: 16
            Image { width: 24; height: 24; source: "assets/compass.svg" }
            UiText { text: root.sceneTitle.toUpperCase(); font.family: "Noto Sans Mono"; font.pixelSize: 15; font.letterSpacing: 4; color: "#655b7c" }
        }
        Row {
            x: 1515; y: 68; spacing: 13
            Rectangle { y: 5; width: 6; height: 6; radius: 3; color: "#8e7da5" }
            UiText { text: root.host.toUpperCase() + "  /  WELCOME HOME"; font.family: "Noto Sans Mono"; font.pixelSize: 11; font.letterSpacing: 1.1; color: "#655b7c"; width: 285; elide: Text.ElideRight }
        }

        // Paper panel keeps every interaction legible over all three wallpapers.
        Rectangle {
            id: paper
            x: 88; y: 145; width: 570; height: 774
            color: "#edf7f4ee"; radius: 4; border.color: "#b6d5cbdc"
            opacity: root.entered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: root.animations ? 1000 : 0 } }
            Rectangle { x: 6; y: 6; width: parent.width-12; height: parent.height-12; color: "transparent"; radius: 2; border.color: "#62cbbfd4" }
            Rectangle { x: 53; y: 0; width: 73; height: 3; color: "#8d79a7" }

            UiText { x: 52; y: 37; text: "Re:ゼロ"; font.family: "EB Garamond"; font.pixelSize: 54; font.letterSpacing: -2 }
            UiText { x: 55; y: 105; text: "STARTING LIFE IN ANOTHER WORLD"; font.family: "Noto Sans Mono"; font.pixelSize: 9; font.letterSpacing: 1.5; color: "#7d718c" }
            Rectangle { x: 54; y: 142; width: 462; height: 1; color: "#ddd4df" }

            UiText { x: 54; y: 177; text: "A MOMENT BETWEEN CHAPTERS"; font.family: "Noto Sans Mono"; font.pixelSize: 10; font.letterSpacing: 2.1; color: "#837391" }
            UiText { x: 50; y: 202; text: "Welcome back."; font.family: "EB Garamond"; font.pixelSize: 61; font.letterSpacing: -1.8 }
            UiText { x: 55; y: 283; text: root.sceneMode===1 ? "Some promises are worth another beginning." : root.sceneMode===2 ? "No matter how many times. Begin again." : "Every return is a new beginning."; font.pixelSize: 15; color: "#7d7588" }

            Item {
                id: form; x: 54; y: 338; width: 462; height: 360
                enabled: !root.busy
                UiText { text: "ACCOUNT"; font.family: "Noto Sans Mono"; font.pixelSize: 12; font.letterSpacing: 2; color: "#746681" }
                TextField {
                    id: username; objectName: "username"
                    x: 0; y: 24; width: 462; height: 54
                    text: userModel.lastUser; placeholderText: "Username"
                    leftPadding: 48; rightPadding: 16; color: root.ink
                    font.family: "Noto Sans"; font.pixelSize: 17
                    maximumLength: 256; selectByMouse: true
                    Accessible.name: "Username"
                    inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                    background: Rectangle { color: username.activeFocus ? "#fcfaf5" : "#72f2efe7"; radius: 3; border.color: username.activeFocus ? "#9680b1" : "#d8cddd"; border.width: username.activeFocus ? 2 : 1 }
                    Canvas { x: 19; y: 17; width: 18; height: 23; onPaint: { var c=getContext("2d"); c.strokeStyle="#837391"; c.lineWidth=1.4; c.beginPath(); c.arc(8,5,4,0,Math.PI*2); c.stroke(); c.beginPath(); c.moveTo(1,21); c.lineTo(1,18); c.bezierCurveTo(1,10,15,10,15,18); c.lineTo(15,21); c.stroke(); } }
                    onAccepted: password.forceActiveFocus()
                    KeyNavigation.tab: password
                }
                UiText { y: 98; text: "PASSWORD"; font.family: "Noto Sans Mono"; font.pixelSize: 12; font.letterSpacing: 2; color: "#746681" }
                UiText { y: 98; anchors.right: parent.right; text: "CAPS LOCK IS ON"; visible: keyboard.capsLock; color: "#a26169"; font.pixelSize: 10 }
                TextField {
                    id: password; objectName: "password"
                    x: 0; y: 122; width: 462; height: 56
                    placeholderText: "Enter your password"; placeholderTextColor: "#9b92a0"
                    leftPadding: 48; rightPadding: 52; color: root.ink
                    font.family: "Noto Sans"; font.pixelSize: 16
                    maximumLength: 4096; selectByMouse: true
                    echoMode: root.revealPassword ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "●"
                    Accessible.name: "Password"
                    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                    background: Rectangle { color: "#faf7f2"; radius: 3; border.color: root.failed ? "#b97f8b" : password.activeFocus ? "#9680b1" : "#d8cddd"; border.width: password.activeFocus ? 2 : 1 }
                    Canvas { x: 18; y: 18; width: 20; height: 22; onPaint: { var c=getContext("2d"); c.strokeStyle="#837391"; c.lineWidth=1.4; c.strokeRect(3,8,13,11); c.beginPath(); c.arc(9.5,8,4,-Math.PI,0); c.stroke(); c.beginPath(); c.moveTo(9.5,12); c.lineTo(9.5,16); c.stroke(); } }
                    onAccepted: root.submit()
                    onTextEdited: { root.failed = false; root.message = ""; }
                    Keys.onEscapePressed: { password.clear(); root.revealPassword = false; root.failed = false; root.message = ""; }
                    KeyNavigation.tab: reveal
                    Button {
                        id: reveal; objectName: "reveal"; x: 412; y: 5; width: 45; height: 46
                        hoverEnabled: true; focusPolicy: Qt.StrongFocus
                        Accessible.name: root.revealPassword ? "Hide password" : "Show password"
                        background: Rectangle { radius: 2; color: reveal.hovered ? "#e9e1ef" : "transparent"; border.width: reveal.activeFocus ? 1 : 0; border.color: root.accent }
                        contentItem: Canvas {
                            onPaint: { var c=getContext("2d"); c.clearRect(0,0,width,height); c.strokeStyle="#837391"; c.lineWidth=1.4; var mx=width/2, my=height/2; c.beginPath(); c.moveTo(mx-9,my); c.quadraticCurveTo(mx,my-10,mx+9,my); c.quadraticCurveTo(mx,my+10,mx-9,my); c.stroke(); c.beginPath(); c.arc(mx,my,2.5,0,Math.PI*2); c.stroke(); }
                        }
                        onClicked: root.revealPassword = !root.revealPassword
                        KeyNavigation.tab: signIn
                    }
                }
                UiButton { id: signIn; objectName: "signIn"; x: 0; y: 201; width: 462; height: 59; primary: true; text: root.busy ? "OPENING…" : "BEGIN AGAIN"; trailing: "→"; onClicked: root.submit(); KeyNavigation.tab: sessionControl }
                UiText { x: 0; y: 274; width: 462; text: root.message; color: root.failed ? "#a26169" : "#71639e"; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }

                Rectangle { y: 313; width: 462; height: 1; color: "#ddd4df" }
                Button {
                    id: sessionControl; objectName: "sessionControl"
                    x: 0; y: 328; width: 462; height: 48; hoverEnabled: true; enabled: sessions.count > 0
                    Accessible.name: "Choose desktop session: " + root.sessionName
                    background: Rectangle { radius: 3; color: sessionControl.hovered ? "#eae3ed" : "transparent"; border.width: sessionControl.activeFocus ? 1 : 0; border.color: root.accent }
                    contentItem: Item {
                        Rectangle { x: 6; y: 17; width: 17; height: 13; radius: 2; color: "transparent"; border.color: "#8e7fa0"; Rectangle { x: 5; y: 16; width: 7; height: 1; color: "#8e7fa0" } }
                        UiText { x: 39; y: 7; text: "DESKTOP SESSION"; font.family: "Noto Sans Mono"; font.pixelSize: 8; font.letterSpacing: 1.1; color: "#8b7e94" }
                        UiText { x: 39; y: 23; width: 365; elide: Text.ElideRight; text: root.sessionName; font.pixelSize: 13; color: "#514960" }
                        UiText { x: 431; y: 13; text: "⌃"; color: "#8e7fa0"; font.pixelSize: 20 }
                    }
                    onClicked: sessionMenu.open()
                    KeyNavigation.tab: sleepControl
                }
                Popup {
                    id: sessionMenu; objectName: "sessionMenu"
                    x: 0; y: 325-height; width: 462; padding: 8
                    height: sessionOptions.implicitHeight+16
                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside; focus: true
                    background: Rectangle { color: "#f8f4ee"; radius: 3; border.color: "#b6a4c8" }
                    contentItem: Column {
                        id: sessionOptions; spacing: 4
                        Repeater {
                            id: sessions; model: sessionModel
                            onCountChanged: Qt.callLater(root.chooseSession)
                            delegate: UiButton {
                                required property var model
                                required property int index
                                property string sessionFile: model.file
                                property string sessionLabel: model.name
                                objectName: "session-"+index; width: 446; height: 48
                                text: sessionLabel; primary: root.sessionIndex === index
                                glyph: root.sessionIndex === index ? "✓" : ""
                                onClicked: root.selectSession(index)
                            }
                        }
                    }
                }
            }
        }

        Column {
            x: 1470; y: 157; width: 330; spacing: 2
            UiText { width: 330; text: Qt.formatDateTime(root.now,"HH:mm"); horizontalAlignment: Text.AlignRight; font.family: "EB Garamond"; font.pixelSize: 92; color: "#5e5274"; font.letterSpacing: -2 }
            UiText { width: 330; text: Qt.formatDateTime(root.now,"dddd, d MMMM").toUpperCase(); horizontalAlignment: Text.AlignRight; font.family: "Noto Sans Mono"; font.pixelSize: 11; color: "#7c6d8c"; font.letterSpacing: 1.8 }
        }
        // A small celestial seal and chapter title anchor the illustration.
        Sigil { x: 723; y: 230; width: 71; height: 71; motionEnabled: root.animations; opacity: .65 }
        Rectangle {
            x: 733; y: 773; width: 1000; height: 198; color: "transparent"
            Rectangle { anchors.fill: parent; gradient: Gradient { GradientStop { position: 0; color: "#00f2efe7" } GradientStop { position: 1; color: "#e8f2efe7" } } }
            UiText { x: 24; y: 25; text: "ここから、もう一度。"; font.family: "Noto Serif CJK JP"; font.pixelSize: 22; color: "#847096"; font.letterSpacing: 4 }
            UiText { x: 21; y: 62; text: root.sceneMode===1 ? "A promise worth keeping." : root.sceneMode===2 ? "This time, a different ending." : "From here, once more."; font.family: "EB Garamond"; font.pixelSize: 51; font.letterSpacing: -.6; color: "#655475" }
            Row { x: 25; y: 143; spacing: 16; Rectangle { y: 7; width: 44; height: 1; color: "#a797b5" } UiText { text: "THE NEXT CHAPTER IS YOURS TO WRITE"; font.family: "Noto Sans Mono"; font.pixelSize: 10; font.letterSpacing: 1.7; color: "#8a7899" } }
        }

        Row {
            x: 93; y: 960; spacing: 14; enabled: !root.busy
            UiButton { id: sleepControl; objectName: "sleep"; width: 157; height: 40; text: "Sleep"; glyph: "☾"; quiet: true; enabled: sddm.canSuspend; onClicked: root.requestPower("Sleep"); KeyNavigation.tab: restartControl }
            UiButton { id: restartControl; objectName: "restart"; width: 157; height: 40; text: "Restart"; glyph: "↻"; quiet: true; enabled: sddm.canReboot; onClicked: root.requestPower("Restart"); KeyNavigation.tab: offControl }
            UiButton { id: offControl; objectName: "powerOff"; width: 157; height: 40; text: "Power off"; glyph: "⏻"; quiet: true; enabled: sddm.canPowerOff; onClicked: root.requestPower("Power off"); KeyNavigation.tab: username }
        }
        Row { x: 1495; y: 983; spacing: 12; UiText { text: "✧"; color: "#9a88aa"; font.pixelSize: 18 } UiText { text: "RE:ZERO  /  " + root.sceneTitle.toUpperCase(); font.family: "Noto Sans Mono"; font.pixelSize: 10; font.letterSpacing: 1.7; color: "#877794" } }

        Rectangle {
            id: failureTint; anchors.fill: parent; color: "#79518e"; opacity: 0
            SequentialAnimation { id: failurePulse; NumberAnimation { target: failureTint; property: "opacity"; to: .14; duration: 90 } NumberAnimation { target: failureTint; property: "opacity"; to: 0; duration: 850 } }
        }
        Rectangle {
            id: transition; anchors.fill: parent; color: "#f2efe7"
            opacity: root.signedIn ? 1 : 0; visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: root.animations ? 700 : 0 } }
            MouseArea { anchors.fill: parent }
            Sigil { x: 909; y: 377; width: 102; height: 102; motionEnabled: root.animations }
            UiText { y: 520; width: 1920; text: "Your next chapter awaits."; font.family: "EB Garamond"; font.pixelSize: 58; horizontalAlignment: Text.AlignHCenter }
            UiText { y: 608; width: 1920; text: root.preview ? "PREVIEW COMPLETE · WELCOME BACK" : "WELCOME BACK"; color: "#897699"; font.family: "Noto Sans Mono"; font.pixelSize: 12; font.letterSpacing: 3; horizontalAlignment: Text.AlignHCenter }
        }
        Popup {
            id: powerDialog; objectName: "powerDialog"
            x: 675; y: 365; width: 570; height: 350; padding: 40; modal: true; focus: true
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
            Overlay.modal: Rectangle { color: "#6b30344f" }
            background: Rectangle { radius: 4; color: "#f7f3ed"; border.color: "#b6a4c8" }
            contentItem: Item {
                UiText { text: root.powerAction === "Sleep" ? "A little rest?" : root.powerAction === "Restart" ? "Begin once more?" : "Until we meet again."; font.family: "EB Garamond"; font.pixelSize: 39 }
                UiText { y: 70; width: 490; text: root.preview ? "This is a preview. Your computer will stay as it is." : root.powerAction === "Power off" ? "Power off this computer?" : root.powerAction === "Restart" ? "Restart this computer?" : "Put this computer to sleep?"; font.pixelSize: 15; color: "#82758d"; wrapMode: Text.WordWrap; lineHeight: 1.5 }
                Row { y: 177; spacing: 14; UiButton { objectName: "cancelPower"; width: 238; text: "Stay here"; onClicked: powerDialog.close() } UiButton { objectName: "confirmPower"; width: 238; primary: true; text: root.powerAction; onClicked: root.confirmPowerAction() } }
            }
            onClosed: password.forceActiveFocus()
        }
    }
}
