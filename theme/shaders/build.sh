#!/bin/sh
set -eu
cd "$(dirname "$0")"
/usr/lib/qt6/bin/qsb --qt6 -o hair-wind.vert.qsb hair-wind.vert
/usr/lib/qt6/bin/qsb --qt6 -o subaru-wind.vert.qsb subaru-wind.vert
