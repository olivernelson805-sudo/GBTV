#!/usr/bin/env bash
set -Eeuo pipefail

# GBTV update 1.3: install a desktop-session systemd user service.
if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run this update with administrator permission." >&2
  exit 1
fi

if [[ -n "${PKEXEC_UID:-}" ]]; then
  TARGET_USER="$(getent passwd "$PKEXEC_UID" | cut -d: -f1)"
elif [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
  TARGET_USER="$SUDO_USER"
else
  echo "Run the update from the GBTV desktop account." >&2
  exit 1
fi

PASSWD_ENTRY="$(getent passwd "$TARGET_USER" || true)"
if [[ -z "$PASSWD_ENTRY" ]]; then
  echo "Could not find desktop user '$TARGET_USER'." >&2
  exit 1
fi
TARGET_HOME="$(cut -d: -f6 <<<"$PASSWD_ENTRY")"
TARGET_GROUP="$(id -gn "$TARGET_USER")"
APP_START="/opt/gbtv/pi/start-gbtv.sh"
APP_FILE="/opt/gbtv/pi/gbtv.py"
if [[ ! -x "$APP_START" || ! -f "$APP_FILE" ]]; then
  echo "GBTV's Python app is not installed at /opt/gbtv/pi yet." >&2
  exit 1
fi
if ! command -v systemctl >/dev/null 2>&1; then
  echo "This Raspberry Pi OS installation does not have systemd." >&2
  exit 1
fi

install -d -m 0755 /etc/systemd/user /usr/local/bin
cat > /etc/systemd/user/gbtv.service <<'SERVICE_UNIT'
[Unit]
Description=GBTV console interface
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
WorkingDirectory=/opt/gbtv
ExecStart=/opt/gbtv/pi/start-gbtv.sh
Restart=on-failure
RestartSec=3
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=default.target
SERVICE_UNIT
chmod 0644 /etc/systemd/user/gbtv.service

cat > /usr/local/bin/gbtv-session-start <<'SESSION_SCRIPT'
#!/bin/sh
set -eu
if [ -n "${DISPLAY:-}" ] && command -v xset >/dev/null 2>&1; then
  xset s off >/dev/null 2>&1 || true
  xset -dpms >/dev/null 2>&1 || true
fi
systemctl --user import-environment DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS >/dev/null 2>&1 || true
if systemctl --user start gbtv.service; then
  exit 0
fi
exec /opt/gbtv/pi/start-gbtv.sh
SESSION_SCRIPT
chmod 0755 /usr/local/bin/gbtv-session-start

AUTOSTART_DIR="$TARGET_HOME/.config/autostart"
install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_GROUP" "$AUTOSTART_DIR"
cat > "$AUTOSTART_DIR/gbtv.desktop" <<'DESKTOP_ENTRY'
[Desktop Entry]
Type=Application
Name=GBTV
Comment=Start the GBTV game console
Exec=/usr/local/bin/gbtv-session-start
Terminal=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=2
DESKTOP_ENTRY
chown "$TARGET_USER:$TARGET_GROUP" "$AUTOSTART_DIR/gbtv.desktop"
chmod 0644 "$AUTOSTART_DIR/gbtv.desktop"

# The service is started from desktop autostart, so boot into an auto-logged-in desktop.
if command -v raspi-config >/dev/null 2>&1; then
  if ! raspi-config nonint do_boot_behaviour B4; then
    echo "GBTV service is installed. Enable Desktop Auto Login in raspi-config if the Pi stops at the login screen." >&2
  fi
fi

systemctl --user disable gbtv.service >/dev/null 2>&1 || true
systemctl --global disable gbtv.service >/dev/null 2>&1 || true
systemctl daemon-reload
systemctl --user daemon-reload >/dev/null 2>&1 || true

if command -v systemd-run >/dev/null 2>&1; then
  systemd-run --quiet --unit=gbtv-update-reboot --on-active=10s /usr/bin/systemctl reboot
else
  shutdown -r +1 "GBTV update 1.3 complete"
fi

echo "GBTV update 1.3 installed. GBTV will start as a systemd user service at desktop login. The Pi will reboot shortly."
set -eu
if [ -n "${DISPLAY:-}" ] && command -v xset >/dev/null 2>&1; then
  xset s off >/dev/null 2>&1 || true
  xset -dpms >/dev/null 2>&1 || true
fi
exec /opt/gbtv/pi/start-gbtv.sh
SESSION_SCRIPT
chmod 0755 /usr/local/bin/gbtv-session-start

AUTOSTART_DIR="$TARGET_HOME/.config/autostart"
install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_GROUP" "$AUTOSTART_DIR"
cat > "$AUTOSTART_DIR/gbtv.desktop" <<'DESKTOP_ENTRY'
[Desktop Entry]
Type=Application
Name=GBTV
Comment=Start the GBTV game console
Exec=/usr/local/bin/gbtv-session-start
Terminal=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=2
DESKTOP_ENTRY
chown "$TARGET_USER:$TARGET_GROUP" "$AUTOSTART_DIR/gbtv.desktop"
chmod 0644 "$AUTOSTART_DIR/gbtv.desktop"

if command -v systemd-run >/dev/null 2>&1; then
  systemd-run --quiet --unit=gbtv-update-reboot --on-active=10s /usr/bin/systemctl reboot
elif command -v shutdown >/dev/null 2>&1; then
  shutdown -r +1 "GBTV update 1.2 complete"
else
  echo "GBTV update 1.2 is installed, but automatic reboot could not be scheduled." >&2
  exit 1
fi

echo "GBTV update 1.2 is installed. The Pi will reboot shortly."
