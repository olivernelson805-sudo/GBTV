#!/usr/bin/env bash
set -Eeuo pipefail

# GBTV update 1.1: install the existing Python console and start it at boot.
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
if [[ ! -x /opt/gbtv/pi/start-gbtv.sh || ! -f /opt/gbtv/pi/gbtv.py ]]; then
  echo "GBTV's Python app is not installed at /opt/gbtv/pi yet. Install the GBTV app files first." >&2
  exit 1
fi

apt-get update
apt-get install -y git python3-tk python3-evdev bluez retroarch \
  libretro-gambatte libretro-mgba
usermod -aG input "$TARGET_USER"

AUTOSTART_DIR="$TARGET_HOME/.config/autostart"
install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_GROUP" "$AUTOSTART_DIR"
install -m 0644 -o "$TARGET_USER" -g "$TARGET_GROUP" \
  /opt/gbtv/pi/gbtv.desktop "$AUTOSTART_DIR/gbtv.desktop"

if command -v systemctl >/dev/null 2>&1; then
  systemctl disable --now gbtv-ui.service >/dev/null 2>&1 || true
fi

if command -v raspi-config >/dev/null 2>&1; then
  if ! raspi-config nonint do_boot_behaviour B4; then
    echo "GBTV startup is set. Enable Desktop Auto Login in raspi-config if the Pi still stops at the login screen." >&2
  fi
else
  echo "GBTV startup is set. Enable Desktop Auto Login in Raspberry Pi Configuration if the Pi still stops at the login screen." >&2
fi

echo "GBTV update 1.1 is installed for $TARGET_USER. Restart the Pi to launch the console automatically."
