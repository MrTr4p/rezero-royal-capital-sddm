#pragma once
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QSettings>
#include <QFileInfo>
#include <QDir>
#include <QSysInfo>
#include <QStandardPaths>
#include <QDebug>

inline QObject *qmlObject(QQmlEngine *engine, const QByteArray &source) {
    QQmlComponent c(engine); c.setData(source, QUrl()); auto object = c.create();
    if (!object) { qCritical() << c.errors(); qFatal("Could not create preview context"); }
    object->setParent(engine); return object;
}
inline QObject *setupContext(QQmlEngine *engine, const QString &theme) {
    auto backend = qmlObject(engine, R"QML(import QtQuick
QtObject {
    id: demo
    property string hostName: ""
    property bool canPowerOff: true
    property bool canReboot: true
    property bool canSuspend: true
    property bool accepted: false
    property bool automaticResponse: true
    property int calls: 0
    property int rebootCalls: 0
    property int powerOffCalls: 0
    property int suspendCalls: 0
    property string submittedUser: ""
    property int submittedSession: -1
    signal loginFailed()
    signal loginSucceeded()
    property Timer response: Timer {
        interval: 800
        onTriggered: { if (demo.accepted) demo.loginSucceeded(); else demo.loginFailed(); demo.accepted = false; }
    }
    function login(user, password, index) {
        calls++; submittedUser = user; submittedSession = index;
        accepted = password === "test";
        if (automaticResponse) response.restart();
    }
    function reboot() { rebootCalls++; }
    function powerOff() { powerOffCalls++; }
    function suspend() { suspendCalls++; }
})QML");
    backend->setProperty("hostName", QSysInfo::machineHostName());
    engine->rootContext()->setContextProperty("sddm", backend);
    engine->rootContext()->setContextProperty("previewMode", true);
    auto config = qmlObject(engine, R"QML(import QtQuick
QtObject { property var values: ({}); function stringValue(key) { return String(values[key] === undefined ? "" : values[key]); } })QML");
    QSettings settings(QFileInfo(theme).dir().filePath("theme.conf"), QSettings::IniFormat);
    QVariantMap values;
    for (const auto &key : settings.allKeys()) values.insert(key, settings.value(key));
    const auto background = qEnvironmentVariable("REZERO_PREVIEW_BACKGROUND");
    if (!background.isEmpty()) values.insert("Background", background);
    const auto motion = qEnvironmentVariable("REZERO_PREVIEW_MOTION");
    if (!motion.isEmpty()) values.insert("MotionLevel", motion);
    config->setProperty("values", values);
    engine->rootContext()->setContextProperty("config", config);
    engine->rootContext()->setContextProperty("keyboard", qmlObject(engine, R"QML(import QtQuick
QtObject { property bool capsLock: false })QML"));
    auto users = qmlObject(engine, R"QML(import QtQuick
QtObject { property string lastUser: "" })QML");
    users->setProperty("lastUser", qEnvironmentVariable("USER"));
    engine->rootContext()->setContextProperty("userModel", users);
    auto sessions = qmlObject(engine, R"QML(import QtQuick
ListModel { property int lastIndex: 0; function addSession(label, filename) { append({name: label, file: filename}); } }
)QML");
    for (const auto &path : {"/usr/share/wayland-sessions", "/usr/share/xsessions"}) {
        QDir dir(path);
        for (const auto &name : dir.entryList({"*.desktop"}, QDir::Files, QDir::Name)) {
            QSettings desktop(dir.filePath(name), QSettings::IniFormat);
            desktop.beginGroup("Desktop Entry");
            if (desktop.value("Hidden", false).toBool()) continue;
            auto executable = desktop.value("TryExec").toString();
            if (!executable.isEmpty() && QStandardPaths::findExecutable(executable).isEmpty()) continue;
            auto label = desktop.value("Name", name).toString();
            QMetaObject::invokeMethod(sessions, "addSession", Q_ARG(QVariant,label), Q_ARG(QVariant,name));
        }
    }
    engine->rootContext()->setContextProperty("sessionModel", sessions);
    return backend;
}
