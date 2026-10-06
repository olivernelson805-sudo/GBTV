#!/usr/bin/env bash
set -Eeuo pipefail

# GBTV installer/updater. Upload this file together with README.md, pi/, and docs/.
# The app passes the commit SHA it checked. Manual use defaults to the latest main.
REPOSITORY="olivernelson805-sudo/GBTV"
BRANCH="main"
COMMIT_SHA="${1:-}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run this script with administrator permission (for example: sudo ./update.sh)." >&2
  exit 1
fi

apt-get update
apt-get install -y ca-certificates curl

if [[ -z "$COMMIT_SHA" ]]; then
  COMMIT_SHA="$(curl -fsSL "https://api.github.com/repos/${REPOSITORY}/commits/${BRANCH}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["sha"])')"
fi
if [[ ! "$COMMIT_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Could not determine a valid GBTV GitHub commit." >&2
  exit 1
fi

if [[ -n "${PKEXEC_UID:-}" ]]; then
  TARGET_USER="$(getent passwd "$PKEXEC_UID" | cut -d: -f1)"
elif [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
  TARGET_USER="$SUDO_USER"
else
  echo "Run the update from the GBTV desktop account so it can configure that account's startup." >&2
  exit 1
fi

PASSWD_ENTRY="$(getent passwd "$TARGET_USER" || true)"
if [[ -z "$PASSWD_ENTRY" ]]; then
  echo "Could not find the desktop account '$TARGET_USER'." >&2
  exit 1
fi
TARGET_HOME="$(cut -d: -f6 <<<"$PASSWD_ENTRY")"
TARGET_GROUP="$(id -gn "$TARGET_USER")"
if [[ ! -d "$TARGET_HOME" || "$TARGET_HOME" == "/root" ]]; then
  echo "The selected desktop account does not have a usable home folder." >&2
  exit 1
fi

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

ARCHIVE="$TEMP_DIR/gbtv.tar.gz"
curl --proto '=https' --tlsv1.2 -fsSL --retry 2 \
  "https://codeload.github.com/${REPOSITORY}/tar.gz/${COMMIT_SHA}" \
  -o "$ARCHIVE"
mkdir -p "$TEMP_DIR/source"
tar -xzf "$ARCHIVE" -C "$TEMP_DIR/source"
PROJECT_DIR="$(find "$TEMP_DIR/source" -mindepth 1 -maxdepth 1 -type d -print -quit)"

for required in pi/gbtv.py pi/gbtv_services.py pi/start-gbtv.sh pi/gbtv.desktop; do
  if [[ ! -f "$PROJECT_DIR/$required" ]]; then
    echo "The GitHub project is missing $required. Upload the GBTV pi/ folder with update.sh, then try again." >&2
    exit 1
  fi
done

apt-get install -y python3-tk python3-evdev bluez retroarch \
  libretro-gambatte libretro-mgba

install -d -m 0755 /opt/gbtv/pi
cp -a "$PROJECT_DIR/pi/." /opt/gbtv/pi/
if [[ -d "$PROJECT_DIR/docs" ]]; then
  install -d -m 0755 /opt/gbtv/docs
  cp -a "$PROJECT_DIR/docs/." /opt/gbtv/docs/
fi
if [[ -f "$PROJECT_DIR/README.md" ]]; then
  install -m 0644 "$PROJECT_DIR/README.md" /opt/gbtv/README.md
fi
chmod 0755 /opt/gbtv/pi/start-gbtv.sh /opt/gbtv/pi/install-emulators.sh

# Turn off the previous browser kiosk service if an older GBTV build installed it.
if command -v systemctl >/dev/null 2>&1; then
  systemctl disable --now gbtv-ui.service >/dev/null 2>&1 || true
fi

usermod -aG input "$TARGET_USER"
AUTOSTART_DIR="$TARGET_HOME/.config/autostart"
install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_GROUP" "$AUTOSTART_DIR"
install -m 0644 -o "$TARGET_USER" -g "$TARGET_GROUP" \
  /opt/gbtv/pi/gbtv.desktop "$AUTOSTART_DIR/gbtv.desktop"

if command -v raspi-config >/dev/null 2>&1; then
  if raspi-config nonint do_boot_behaviour B4; then
    echo "Configured Raspberry Pi OS to boot to the desktop with automatic login."
  else
    echo "GBTV desktop startup is installed; enable Desktop Auto Login in raspi-config to launch it after power-on." >&2
  fi
else
  echo "GBTV desktop startup is installed; enable Desktop Auto Login in Raspberry Pi Configuration to launch it after power-on." >&2
fi

echo "GBTV has been installed for $TARGET_USER and will start when that user's desktop opens."
echo "Restart the Pi to start GBTV automatically. The new input-group permission also takes effect after restart."
