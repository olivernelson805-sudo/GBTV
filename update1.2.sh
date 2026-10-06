#!/usr/bin/env bash
set -Eeuo pipefail

# GBTV update 1.2: keep the TV display awake and start the console cleanly.
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

# This runs as the desktop user, so xset can reach that user's display session.
install -d -m 0755 /usr/local/bin
cat > /usr/local/bin/gbtv-session-start <<'SESSION_SCRIPT'
#!/bin/sh
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

echo "GBTV update 1.2 is installed. The display will stay awake during play, and GBTV will launch at desktop login. Restart the Pi to use it."
