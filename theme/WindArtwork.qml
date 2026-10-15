import QtQuick

Item {
    id: artwork
    property url source
    property bool motionEnabled: true
    property bool hairSwayEnabled: true
    property real elapsedMs: 0
    property int sceneMode: 0
    property real windStrength: 1
    readonly property bool shaderAvailable: GraphicsInfo.api !== GraphicsInfo.Software && GraphicsInfo.api !== GraphicsInfo.Unknown

    Image {
        id: texture
        anchors.fill: parent
        source: artwork.source
        fillMode: Image.PreserveAspectCrop
        visible: !wind.visible
    }
    ShaderEffect {
        id: wind
        objectName: "hairWind"
        anchors.fill: parent
        visible: artwork.motionEnabled && artwork.hairSwayEnabled && artwork.shaderAvailable
        property variant source: texture
        property real windSeconds: artwork.elapsedMs / 1000
        property real windStrength: artwork.windStrength
        property real sceneMode: artwork.sceneMode
        property real itemWidth: width
        property real itemHeight: height
        property real cropV: texture.sourceSize.height > 0 ? Math.min(1, (height / width) * (texture.sourceSize.width / texture.sourceSize.height)) : 1
        property real cropU: texture.sourceSize.width > 0 ? Math.min(1, (width / height) / (texture.sourceSize.width / texture.sourceSize.height)) : 1
        mesh: GridMesh { resolution: Qt.size(128, 80) }
        vertexShader: artwork.sceneMode>0 ? "shaders/subaru-wind.vert.qsb" : "shaders/hair-wind.vert.qsb"
    }
}
