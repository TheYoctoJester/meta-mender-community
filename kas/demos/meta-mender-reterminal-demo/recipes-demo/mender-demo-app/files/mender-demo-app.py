#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# Mender OTA Demo Application for Seeed Studio reTerminal
# Displays Mender device state, artifact info, and network status
# in a fullscreen kiosk-style GTK3 window.

import subprocess
import socket

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gtk, Gdk, GLib, GdkPixbuf

DEMO_VERSION = "@DEMO_VERSION@"
APP_DIR = "/opt/mender-demo-app"
CSS_PATH = APP_DIR + "/theme.css"
LOGO_PATH = APP_DIR + "/mender-logo.svg"


def get_mender_provides():
    """Query mender-update for artifact provides."""
    info = {"artifact_name": "unknown", "artifact_group": ""}
    try:
        result = subprocess.run(
            ["mender-update", "show-provides"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            for line in result.stdout.strip().splitlines():
                if "=" in line:
                    key, _, value = line.partition("=")
                    key = key.strip()
                    value = value.strip()
                    if key == "artifact_name":
                        info["artifact_name"] = value
                    elif key == "artifact_group":
                        info["artifact_group"] = value
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return info


def get_mender_auth_state():
    """Check Mender authentication state via D-Bus."""
    try:
        from pydbus import SystemBus
        bus = SystemBus()
        mender = bus.get("io.mender.AuthenticationManager",
                         "/io/mender/AuthenticationManager")
        jwt = mender.GetJwtToken()
        if jwt and len(jwt) > 0 and jwt[0]:
            return "Authenticated"
        return "Not authenticated"
    except Exception:
        return "Mender not running"


def get_default_interface():
    """Get the name of the default network interface from /proc/net/route."""
    try:
        with open("/proc/net/route", "r") as f:
            for line in f.readlines()[1:]:
                fields = line.strip().split()
                if len(fields) >= 2 and fields[1] == "00000000":
                    return fields[0]
    except (IOError, IndexError):
        pass
    return None


def get_ip_address():
    """Get the IP address and interface name of the default route."""
    iface = get_default_interface()
    if not iface:
        return "No network", ""

    try:
        # Use a UDP socket to determine the source IP for external traffic
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(1)
        s.connect(("8.8.8.8", 53))
        ip = s.getsockname()[0]
        s.close()
        return ip, iface
    except (OSError, socket.error):
        pass

    # Fallback: try to read from /proc/net/fib_trie or hostname
    try:
        hostname = socket.gethostname()
        ip = socket.gethostbyname(hostname)
        if ip and not ip.startswith("127."):
            return ip, iface or "unknown"
    except socket.error:
        pass

    return "No network", ""


class MenderDemoWindow(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Mender Demo")

        self.load_css()
        self.set_name("main-window")
        self.fullscreen()

        # Main vertical layout
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        vbox.set_name("main-container")
        self.add(vbox)

        # Content area (expands to fill)
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        content.set_name("content-area")
        content.set_valign(Gtk.Align.CENTER)
        content.set_halign(Gtk.Align.CENTER)
        vbox.pack_start(content, True, True, 0)

        # Mender logo
        self.logo = Gtk.Image()
        self.load_logo()
        content.pack_start(self.logo, False, False, 16)

        # Title
        title = Gtk.Label(label="Mender Demo Application")
        title.set_name("title-label")
        content.pack_start(title, False, False, 0)

        # Version
        version = Gtk.Label(label="Version " + DEMO_VERSION)
        version.set_name("version-label")
        content.pack_start(version, False, False, 0)

        # Spacer
        content.pack_start(Gtk.Box(), False, False, 8)

        # Artifact info
        self.artifact_label = Gtk.Label(label="Artifact: ...")
        self.artifact_label.set_name("info-label")
        content.pack_start(self.artifact_label, False, False, 4)

        # Auth state
        auth_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        auth_box.set_halign(Gtk.Align.CENTER)
        self.auth_indicator = Gtk.Label()
        self.auth_indicator.set_name("auth-indicator")
        auth_box.pack_start(self.auth_indicator, False, False, 0)
        self.auth_label = Gtk.Label(label="Device state: ...")
        self.auth_label.set_name("info-label")
        auth_box.pack_start(self.auth_label, False, False, 0)
        content.pack_start(auth_box, False, False, 4)

        # Footer bar
        footer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        footer.set_name("footer-bar")

        self.ip_label = Gtk.Label(label="IP: ...")
        self.ip_label.set_name("footer-label")
        self.ip_label.set_halign(Gtk.Align.START)
        footer.pack_start(self.ip_label, True, True, 16)

        self.iface_label = Gtk.Label(label="")
        self.iface_label.set_name("footer-label")
        self.iface_label.set_halign(Gtk.Align.END)
        footer.pack_end(self.iface_label, False, False, 16)

        vbox.pack_end(footer, False, False, 0)

        # Initial data load
        self.update_mender_state()
        self.update_ip_address()

        # Periodic updates
        GLib.timeout_add_seconds(5, self.update_mender_state)
        GLib.timeout_add_seconds(30, self.update_ip_address)

        self.show_all()

    def load_css(self):
        """Load the GTK CSS theme file."""
        css_provider = Gtk.CssProvider()
        try:
            css_provider.load_from_path(CSS_PATH)
            screen = Gdk.Screen.get_default()
            Gtk.StyleContext.add_provider_for_screen(
                screen, css_provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            )
        except GLib.Error as e:
            print("Warning: Could not load CSS theme: " + str(e))

    def load_logo(self):
        """Load and display the Mender logo SVG."""
        try:
            pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(
                LOGO_PATH, 200, 80, True
            )
            self.logo.set_from_pixbuf(pixbuf)
        except GLib.Error:
            # Fallback: show text instead of logo
            self.logo.set_from_icon_name("image-missing", Gtk.IconSize.DIALOG)

    def update_mender_state(self):
        """Poll Mender for artifact and auth info."""
        provides = get_mender_provides()
        self.artifact_label.set_text(
            "Artifact: " + provides["artifact_name"]
        )

        auth = get_mender_auth_state()
        self.auth_label.set_text("Device state: " + auth)

        if auth == "Authenticated":
            self.auth_indicator.set_markup(
                '<span foreground="#00cc88">●</span>'
            )
        elif auth == "Not authenticated":
            self.auth_indicator.set_markup(
                '<span foreground="#ffaa00">●</span>'
            )
        else:
            self.auth_indicator.set_markup(
                '<span foreground="#ff4444">●</span>'
            )

        return True  # keep the timeout active

    def update_ip_address(self):
        """Poll for current IP address and interface."""
        ip, iface = get_ip_address()
        self.ip_label.set_text("IP: " + str(ip))
        self.iface_label.set_text(str(iface))
        return True  # keep the timeout active


class MenderDemoApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="io.mender.DemoApp")

    def do_activate(self):
        window = MenderDemoWindow(self)
        window.present()
        # Inhibit idle/sleep so the compositor never blanks the display.
        # On Wayland this acquires a zwp_idle_inhibit_v1 inhibitor.
        self.inhibit(window, Gtk.ApplicationInhibitFlags.IDLE, "kiosk mode")


if __name__ == "__main__":
    app = MenderDemoApp()
    app.run(None)
