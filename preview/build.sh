#!/bin/sh
set -eu
cd "$(dirname "$0")"
g++ -std=c++17 -O2 -fPIC preview.cpp -o qt-preview $(pkg-config --cflags --libs Qt6Quick Qt6Gui Qt6Qml)
