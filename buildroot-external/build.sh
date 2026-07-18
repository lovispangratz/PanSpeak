#!/bin/sh
# Baut das AirPlay/HiFiBerry-Amp4-Image auf einem frischen Linux-Host (z. B. VPS).
#
# Aufruf:
#   ./build.sh zero2w   (Standard, Raspberry Pi Zero 2 W, WLAN)
#   ./build.sh pi2b      (Raspberry Pi 2 B, Ethernet + optionaler USB-WLAN-Stick)
#
# Voraussetzungen (Debian/Ubuntu): siehe README.md Phase 0.
set -e

BOARD="${1:-zero2w}"
case "$BOARD" in
    zero2w)
        DEFCONFIG="airplay_defconfig"
        BOARD_DIR="board/airplay"
        ;;
    pi2b)
        DEFCONFIG="airplay_pi2b_defconfig"
        BOARD_DIR="board/airplay-pi2b"
        ;;
    *)
        echo "Unbekanntes Board '$BOARD' (erlaubt: zero2w, pi2b)" >&2
        exit 1
        ;;
esac

BUILDROOT_TAG="2025.02"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILDROOT_DIR="$SCRIPT_DIR/../buildroot"

if [ ! -d "$BUILDROOT_DIR" ]; then
    git clone --depth 1 --branch "$BUILDROOT_TAG" \
        https://gitlab.com/buildroot.org/buildroot.git "$BUILDROOT_DIR"
fi

cd "$BUILDROOT_DIR"
make BR2_EXTERNAL="$SCRIPT_DIR" "$DEFCONFIG"

cat <<EOF

------------------------------------------------------------------
Board: $BOARD ($DEFCONFIG)

Vor dem eigentlichen Build noch pruefen/anpassen (einmalig):

1) WLAN-Zugangsdaten:
   cp $SCRIPT_DIR/$BOARD_DIR/rootfs-overlay/etc/wpa_supplicant.conf.example \\
      $SCRIPT_DIR/$BOARD_DIR/rootfs-overlay/etc/wpa_supplicant.conf
   -> ssid/psk eintragen (diese Datei ist gitignored)
   (beim Pi 2B optional - nur noetig, falls ein USB-WLAN-Stick genutzt wird,
   Ethernet laeuft auch ohne diese Datei per DHCP)

2) Root-Passwort statt Platzhalter setzen:
   cd $BUILDROOT_DIR && make menuconfig
   -> System configuration -> Root password

Danach:
   cd $BUILDROOT_DIR && make
------------------------------------------------------------------
EOF
