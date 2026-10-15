#include <QGuiApplication>
#include <QQuickView>
#include <QKeyEvent>
#include "context.h"
class CapsFilter : public QObject {
    QObject *keyboard;
public:
    explicit CapsFilter(QObject *object): keyboard(object) {}
    bool eventFilter(QObject *, QEvent *event) override {
        if (event->type() == QEvent::KeyPress) {
            auto key = static_cast<QKeyEvent *>(event);
            if (key->key() == Qt::Key_CapsLock && !key->isAutoRepeat())
                keyboard->setProperty("capsLock", !keyboard->property("capsLock").toBool());
        }
        return false;
    }
};
int main(int argc, char **argv) {
    QGuiApplication app(argc, argv);
    if (argc != 2) return 2;
    QQuickView view; view.setTitle("Re:Zero · Royal Capital preview");
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    const QString theme = QString::fromLocal8Bit(argv[1]);
    setupContext(view.engine(), theme);
    CapsFilter keys(view.engine()->rootContext()->contextProperty("keyboard").value<QObject *>());
    app.installEventFilter(&keys);
    view.setSource(QUrl::fromLocalFile(theme));
    if (view.status() != QQuickView::Ready) return 1;
    view.resize(1920, 1080); view.showFullScreen(); view.requestActivate();
    return app.exec();
}
