# buildroot-external — AirPlay-Streamer für HiFiBerry Amp4

Dies ist ein **BR2_EXTERNAL**-Tree (der offizielle Buildroot-Mechanismus für
eigene Board-Dateien außerhalb des Buildroot-Repos). Er enthält alles, was auf
`raspberrypizero2w_defconfig` aufsetzt: Paketauswahl, `config.txt`-Ergänzungen
für den Amp4 und den Rootfs-Overlay (AirPlay-Autostart, ALSA-Routing, Netzwerk).

Ausführliche Erklärung der einzelnen Phasen: siehe
`../buildroot-airplay-pi-zero2w.md` im Repo-Root. Eine Abweichung von dieser
Anleitung: Phase 4.5 (Software-EQ) nutzt **nicht** `alsaequal` — das ist kein
offizielles Buildroot-Paket und kaum gepflegte Software. Stattdessen kommt die
statische EQ-Variante aus Anhang B zum Einsatz (`caps`/Eq10 + alsa-libs
eingebautes `type ladspa`-Plugin, feste Kurve in `asound.conf`, keine
Live-Regelung per `alsamixer -D equal`).

## Voraussetzungen (Build-Host, Debian/Ubuntu)

```bash
sudo apt update
sudo apt install -y build-essential git bc bison flex libssl-dev \
    libncurses-dev python3 unzip rsync wget cpio file
```

~10 GB freier Plattenplatz. Mit mehr CPU-Kernen geht's deutlich schneller als
die in der Anleitung veranschlagten 30–90 Minuten (Buildroot nutzt automatisch
alle Kerne, `BR2_JLEVEL=0`).

## Build

```bash
./build.sh
```

Das Skript klont Buildroot 2025.02 (falls noch nicht vorhanden als
`../buildroot`) und wendet `airplay_defconfig` an. **Vor dem eigentlichen
`make`** unbedingt:

1. **WLAN-Zugangsdaten** eintragen:
   ```bash
   cp board/airplay/rootfs-overlay/etc/wpa_supplicant.conf.example \
      board/airplay/rootfs-overlay/etc/wpa_supplicant.conf
   ```
   `ssid`/`psk` eintragen. Diese Datei ist über `.gitignore` ausgeschlossen —
   niemals echte Zugangsdaten committen.

2. **Root-Passwort** statt Platzhalter setzen (sonst verweigert SSH den
   Root-Login):
   ```bash
   cd ../buildroot && make menuconfig
   # System configuration -> Root password
   ```

Danach:

```bash
cd ../buildroot && make
```

Ergebnis: `../buildroot/output/images/sdcard.img`.

## Auf SD-Karte schreiben & erster Boot

Siehe Phase 9/10 in `../buildroot-airplay-pi-zero2w.md` — `dd`, Amp4 mit
12–20 V versorgen, `ssh root@airplay.local`, Verifikation mit `aplay -l`,
`dmesg | grep hifiberry`, `speaker-test`.

## EQ-Kurve anpassen

`board/airplay/rootfs-overlay/etc/asound.conf`, Zeile `controls [ ... ]` in
`pcm.equal_fixed` — zehn dB-Werte für 31 Hz…16 kHz. Danach neu bauen und
Image neu flashen (oder Datei manuell auf die laufende SD-Karte kopieren und
`shairport-sync` per `/etc/init.d/S99shairport-sync restart` neu starten).
