#!/bin/sh
# Setup fuer einen frischen Ubuntu-Build-VPS (wegwerfbar - nach dem Bauen
# kann der VPS geloescht werden, dieses Script setzt jederzeit einen neuen auf).
#
# Aufruf (nach dem Klonen dieses Repos auf dem VPS):
#   ./setup-vps.sh
#
# Danach die am Ende ausgegebenen Schritte befolgen (Secrets eintragen,
# dann bauen).
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
EXTERNAL_DIR="$REPO_DIR/buildroot-external"
BUILDROOT_DIR="$REPO_DIR/buildroot"
PI2B_OUTPUT_DIR="$REPO_DIR/output-pi2b"
BUILDROOT_TAG="2025.02"

# Buildroot 2025.02s gebuendeltes host-m4 (gnulib) kompiliert nicht mit
# GCC >= 14 (C23-nodiscard-Kollision, siehe README). Neuere Ubuntu-Versionen
# liefern GCC 14/15 als Default - deshalb wird gcc-13 mitinstalliert und
# unten als HOSTCC verwendet.
HOSTCC=gcc-13
HOSTCXX=g++-13

if [ "$(id -u)" -ne 0 ]; then
    SUDO=sudo
else
    SUDO=""
fi

export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update
$SUDO apt-get install -y \
    build-essential git bc bison flex libssl-dev libncurses-dev \
    python3 unzip rsync wget cpio file \
    gcc-13 g++-13

if [ ! -d "$BUILDROOT_DIR" ]; then
    git clone --depth 1 --branch "$BUILDROOT_TAG" \
        https://gitlab.com/buildroot.org/buildroot.git "$BUILDROOT_DIR"
fi

# Defconfigs nur beim allerersten Lauf anwenden: ein erneutes Anwenden wuerde
# die .config zuruecksetzen - inklusive eines dort bereits gesetzten
# Root-Passworts (wieder Platzhalter!).
if [ ! -f "$BUILDROOT_DIR/.config" ]; then
    make -C "$BUILDROOT_DIR" BR2_EXTERNAL="$EXTERNAL_DIR" airplay_defconfig
fi
if [ ! -f "$PI2B_OUTPUT_DIR/.config" ]; then
    make -C "$BUILDROOT_DIR" O="$PI2B_OUTPUT_DIR" \
        BR2_EXTERNAL="$EXTERNAL_DIR" airplay_pi2b_defconfig
fi

cat <<EOF

==================================================================
Setup fertig. Vor dem Bauen einmalig:

1) WLAN-Zugangsdaten (Zero 2 W zwingend; Pi 2B nur fuer USB-WLAN-Stick):
   cp $EXTERNAL_DIR/board/airplay/rootfs-overlay/etc/wpa_supplicant.conf.example \\
      $EXTERNAL_DIR/board/airplay/rootfs-overlay/etc/wpa_supplicant.conf
   (ssid/psk eintragen; fuer Pi 2B analog unter board/airplay-pi2b/)

2) Root-Passwoerter setzen (je Board eigene .config):
   cd $BUILDROOT_DIR && make menuconfig
   cd $BUILDROOT_DIR && make O=$PI2B_OUTPUT_DIR menuconfig
   -> System configuration -> Root password

Bauen (nutzt alle CPU-Kerne):

   cd $BUILDROOT_DIR
   make HOSTCC=$HOSTCC HOSTCXX=$HOSTCXX                        # Zero 2 W
   make O=$PI2B_OUTPUT_DIR HOSTCC=$HOSTCC HOSTCXX=$HOSTCXX    # Pi 2B

Images:
   $BUILDROOT_DIR/output/images/sdcard.img    (Zero 2 W)
   $PI2B_OUTPUT_DIR/images/sdcard.img         (Pi 2B)
==================================================================
EOF
