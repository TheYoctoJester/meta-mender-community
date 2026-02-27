#!/bin/sh
# Launch wrapper for the Mender Demo Application
# Sets up the Wayland environment to connect to Weston

export XDG_RUNTIME_DIR=/run
export WAYLAND_DISPLAY=wayland-0
export GDK_BACKEND=wayland
export GI_TYPELIB_PATH=/usr/lib/girepository-1.0
exec dbus-run-session -- python3 /opt/mender-demo-app/mender-demo-app.py
