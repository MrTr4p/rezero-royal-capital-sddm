#!/bin/sh
set -eu
cd "$(dirname "$0")"
g++ -std=c++17 -O2 -fPIC theme-tests.cpp -o theme-tests $(pkg-config --cflags --libs Qt6Quick Qt6Gui Qt6Qml Qt6Test)
QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QUICK_CONTROLS_STYLE=Basic ./theme-tests "$PWD/../theme/Main.qml"
