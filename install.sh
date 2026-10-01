#!/usr/bin/env bash
# Install or upgrade the plasmoid for the current user.
set -euo pipefail
cd "$(dirname "$0")"
if kpackagetool6 -t Plasma/Applet -l | grep -qx org.maros.daguwidget; then
    kpackagetool6 -t Plasma/Applet -u package
else
    kpackagetool6 -t Plasma/Applet -i package
fi
