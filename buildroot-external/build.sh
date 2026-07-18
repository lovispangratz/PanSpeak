#!/bin/sh
# Baut das AirPlay/HiFiBerry-Amp4-Image auf einem frischen Linux-Host (z. B. VPS).
#
# Voraussetzungen (Debian/Ubuntu): siehe README.md Phase 0.
set -e

BUILDROOT_TAG="2025.02"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILDROOT_DIR="$SCRIPT_DIR/../buildroot"

if [ ! -d "$BUILDROOT_DIR" ]; then
    git clone --depth 1 --branch "$BUILDROOT_TAG" \
        https://gitlab.com/buildroot.org/buildroot.git "$BUILDROOT_DIR"
fi

cd "$BUILDROOT_DIR"
make BR2_EXTERNAL="$SCRIPT_DIR" airplay_defconfig

cat <<EOF

------------------------------------------------------------------
Vor dem eigentlichen Build noch pruefen/anpassen (einmalig):

1) WLAN-Zugangsdaten:
   cp $SCRIPT_DIR/board/airplay/rootfs-overlay/etc/wpa_supplicant.conf.example \\
      $SCRIPT_DIR/board/airplay/rootfs-overlay/etc/wpa_supplicant.conf
   -> ssid/psk eintragen (diese Datei ist gitignored)

2) Root-Passwort statt Platzhalter setzen:
   cd $BUILDROOT_DIR && make menuconfig
   -> System configuration -> Root password

Danach:
   cd $BUILDROOT_DIR && make
------------------------------------------------------------------
EOF
