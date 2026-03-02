#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# Mender OTA Demo Application for Seeed Studio reTerminal
# Displays Mender device state, artifact info, and network status
# in a fullscreen kiosk-style GTK3 window.
#
# Auth and update state are monitored reactively via D-Bus signals.
# Name-owner watching handles the boot race (app starts before mender).

import subprocess
import socket

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gtk, Gdk, Gio, GLib, GdkPixbuf

DEMO_VERSION = "@DEMO_VERSION@"
APP_DIR = "/opt/mender-demo-app"
CSS_PATH = APP_DIR + "/theme.css"
LOGO_PATH = APP_DIR + "/mender-logo.svg"

# Map demangled C++ state class names to display labels
STATE_LABELS = {
    "InitState": "Initializing",
    "IdleState": "Idle",
    "ScheduleNextPollState": "Scheduling",
    "SubmitInventoryState": "Sending inventory",
    "PollForDeploymentState": "Checking for update",
    "SendStatusUpdateState": "Reporting status",
    "UpdateDownloadState": "Downloading",
    "UpdateDownloadCancelState": "Cancelling download",
    "UpdateInstallState": "Installing",
    "UpdateCheckRebootState": "Checking reboot",
    "UpdateRebootState": "Rebooting",
    "UpdateVerifyRebootState": "Verifying reboot",
    "UpdateBeforeCommitState": "Preparing commit",
    "UpdateCommitState": "Committing",
    "UpdateAfterCommitState": "Finalizing commit",
    "UpdateCheckRollbackState": "Checking rollback",
    "UpdateRollbackState": "Rolling back",
    "UpdateRollbackRebootState": "Rollback reboot",
    "UpdateVerifyRollbackRebootState": "Verifying rollback",
    "UpdateRollbackSuccessfulState": "Rollback complete",
    "UpdateFailureState": "Update failed",
    "UpdateSaveProvidesState": "Saving provides",
    "UpdateCleanupState": "Cleaning up",
    "ClearArtifactDataState": "Clearing data",
    "StateLoopState": "State loop",
    "EndOfDeploymentState": "Deployment complete",
    "ExitState": "Exiting",
    "StateScriptState": "Running script",
    "SaveStateScriptState": "Running script",
}

# States that signal the end of a deployment (trigger artifact re-fetch)
DEPLOYMENT_END_STATES = {"EndOfDeploymentState", "IdleState"}


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
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(1)
        s.connect(("8.8.8.8", 53))
        ip = s.getsockname()[0]
        s.close()
        return ip, iface
    except (OSError, socket.error):
        pass

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

        # Track current update state
        self._update_state = ""
        self._update_proxy = None
        self._heartbeat_on = False

        # Main vertical layout
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        vbox.set_name("main-container")
        self.add(vbox)

        # Content area — logo only, centered
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        content.set_name("content-area")
        content.set_valign(Gtk.Align.CENTER)
        content.set_halign(Gtk.Align.CENTER)
        vbox.pack_start(content, True, True, 0)

        self.logo = Gtk.Image()
        self.load_logo()
        content.pack_start(self.logo, False, False, 0)

        # Footer bar
        footer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        footer.set_name("footer-bar")

        # Left side: version | artifact | state
        left_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        left_box.set_halign(Gtk.Align.START)

        version_label = Gtk.Label(label=DEMO_VERSION)
        version_label.set_name("footer-label")
        left_box.pack_start(version_label, False, False, 0)

        self._add_separator(left_box)

        self.artifact_label = Gtk.Label(label="Artifact: ...")
        self.artifact_label.set_name("footer-label")
        left_box.pack_start(self.artifact_label, False, False, 0)

        self._sep_state = self._add_separator(left_box)

        self.state_label = Gtk.Label(label="")
        self.state_label.set_name("footer-label")
        left_box.pack_start(self.state_label, False, False, 0)

        footer.pack_start(left_box, True, True, 16)

        # Right side: IP (iface) | heartbeat
        right_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        right_box.set_halign(Gtk.Align.END)

        self.ip_label = Gtk.Label(label="...")
        self.ip_label.set_name("footer-label")
        right_box.pack_start(self.ip_label, False, False, 0)

        self._add_separator(right_box)

        self.heartbeat_label = Gtk.Label()
        self.heartbeat_label.set_name("footer-label")
        right_box.pack_start(self.heartbeat_label, False, False, 0)

        footer.pack_end(right_box, False, False, 16)

        vbox.pack_end(footer, False, False, 0)

        # Initial data load
        self._do_update_artifact()
        self.update_ip_address()

        # Set up D-Bus proxy (async, with name-owner watching)
        self._setup_update_proxy()

        # Periodic fallback polls
        GLib.timeout_add_seconds(30, self._do_update_artifact)
        GLib.timeout_add_seconds(5, self.update_ip_address)
        GLib.timeout_add(1000, self._tick_heartbeat)

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
        """Load and display the Mender logo SVG scaled to 85% of screen width."""
        try:
            screen = Gdk.Screen.get_default()
            logo_width = int(screen.get_width() * 0.85)
            # Trimmed SVG viewBox is 662.4 x 164.9
            logo_height = int(logo_width * 164.9 / 662.4)
            pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(
                LOGO_PATH, logo_width, logo_height, True
            )
            self.logo.set_from_pixbuf(pixbuf)
        except GLib.Error:
            self.logo.set_from_icon_name("image-missing", Gtk.IconSize.DIALOG)

    @staticmethod
    def _add_separator(box):
        """Add a pipe separator label to a box and return it."""
        sep = Gtk.Label(label="|")
        sep.set_name("footer-separator")
        box.pack_start(sep, False, False, 0)
        return sep

    def _tick_heartbeat(self):
        """Toggle heartbeat indicator every second."""
        self._heartbeat_on = not self._heartbeat_on
        if self._heartbeat_on:
            self.heartbeat_label.set_markup(
                '<span foreground="#00cc88">\u2665</span>'
            )
        else:
            self.heartbeat_label.set_markup(
                '<span foreground="#006644">\u2665</span>'
            )
        return True  # keep timer active

    # ── Update state D-Bus ────────────────────────────────────────────────

    def _setup_update_proxy(self):
        """Create async update proxy. Watches for service to appear at boot."""
        Gio.DBusProxy.new_for_bus(
            Gio.BusType.SYSTEM,
            Gio.DBusProxyFlags.NONE,
            None,
            "io.mender.UpdateManager",
            "/io/mender/UpdateManager",
            "io.mender.Update1",
            None,
            self._on_update_proxy_ready,
        )

    def _on_update_proxy_ready(self, _source, result):
        """Callback when update D-Bus proxy is ready."""
        try:
            self._update_proxy = Gio.DBusProxy.new_for_bus_finish(result)
            self._update_proxy.connect("g-signal", self._on_update_signal)
            self._update_proxy.connect(
                "notify::g-name-owner", self._on_update_owner_changed
            )
            # Service may already be running
            if self._update_proxy.get_name_owner():
                self._do_update_state_check()
        except GLib.Error as e:
            print("Warning: Could not create update proxy: " + str(e))

    def _on_update_owner_changed(self, proxy, _pspec):
        """Called when mender-update appears or disappears on the bus."""
        if proxy.get_name_owner():
            self._do_update_state_check()
        else:
            self._set_update_state("")

    def _do_update_state_check(self):
        """Query current update state via the proxy."""
        try:
            result = self._update_proxy.call_sync(
                "GetCurrentState", None, Gio.DBusCallFlags.NONE, 5000, None
            )
            (state_name,) = result.unpack()
            self._set_update_state(state_name)
        except GLib.Error:
            self._set_update_state("")

    def _on_update_signal(self, _proxy, _sender, signal_name, params):
        """Handle StateChanged signal."""
        if signal_name == "StateChanged":
            (state_name,) = params.unpack()
            self._set_update_state(state_name)

            # Re-fetch artifact after deployment ends
            if state_name in DEPLOYMENT_END_STATES:
                GLib.timeout_add_seconds(1, self._do_update_artifact_once)

    def _set_update_state(self, state_name):
        """Update the state label in the footer."""
        self._update_state = state_name
        label = STATE_LABELS.get(state_name, state_name)
        if label:
            self.state_label.set_text(label)
            self._sep_state.show()
        else:
            self.state_label.set_text("")
            self._sep_state.hide()

    # ── Artifact polling ─────────────────────────────────────────────────

    def _do_update_artifact(self):
        """Poll for artifact info (periodic fallback)."""
        provides = get_mender_provides()
        self.artifact_label.set_text(
            "Artifact: " + provides["artifact_name"]
        )
        return True  # keep the timeout active

    def _do_update_artifact_once(self):
        """Single-shot artifact refresh after deployment end."""
        self._do_update_artifact()
        return False  # do not repeat

    # ── IP polling ───────────────────────────────────────────────────────

    def update_ip_address(self):
        """Poll for current IP address and interface."""
        ip, iface = get_ip_address()
        if iface:
            self.ip_label.set_text(str(ip) + " (" + str(iface) + ")")
        else:
            self.ip_label.set_text(str(ip))
        return True  # keep the timeout active


class MenderDemoApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="io.mender.DemoApp")

    def do_activate(self):
        window = MenderDemoWindow(self)
        window.present()
        # Inhibit idle/sleep so the compositor never blanks the display.
        self.inhibit(window, Gtk.ApplicationInhibitFlags.IDLE, "kiosk mode")


if __name__ == "__main__":
    app = MenderDemoApp()
    app.run(None)
