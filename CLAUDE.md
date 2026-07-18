# CLAUDE.md — Projektkontext für Claude Code

## Was das Projekt ist

Minimaler AirPlay-1-Streamer (shairport-sync) auf Buildroot 2025.02 für den
HiFiBerry **Amp4** (PCM5122-kompatibler Codec, Overlay `hifiberry-dacplus-std`),
in zwei Board-Varianten:

| Board | Defconfig | Netzwerk | Hostname | Status |
|---|---|---|---|---|
| Raspberry Pi Zero 2 W | `airplay_defconfig` | WLAN | `airplay` | gebaut, ungetestet auf Hardware |
| Raspberry Pi 2 B (Rev 1.1) | `airplay_pi2b_defconfig` | Ethernet + opt. USB-WLAN | `airplay-pi2b` | **auf echter Hardware verifiziert, läuft end-to-end** |

## Repo-Layout

- `buildroot-external/` — BR2_EXTERNAL-Tree (Defconfigs, Board-Overlays,
  `build.sh`). Detail-Doku: `buildroot-external/README.md` (Troubleshooting
  dort ist aus echter Hardware-Fehlersuche entstanden — ernst nehmen).
- `buildroot-airplay-pi-zero2w.md` — ursprüngliche Anleitung. **Achtung:**
  Phase 4.5 (alsaequal) und Anhang B (LADSPA-EQ) sind so nicht umsetzbar,
  siehe „Gelernte Lektionen".
- `setup-vps.sh` — provisioniert einen frischen Ubuntu-Build-Host komplett
  (Wegwerf-VPS-Workflow; der Nutzer baut auf einem VPS, nicht lokal).
- `buildroot/` und `output-pi2b/` sind gitignored (Build-Arbeitsverzeichnisse).

## Build-Workflow (Kurzform)

```bash
./setup-vps.sh          # apt-Pakete inkl. gcc-13, Buildroot-Clone, beide Configs
# Secrets: wpa_supplicant.conf (gitignored!) + Root-Passwort via menuconfig
cd buildroot
make HOSTCC=gcc-13 HOSTCXX=g++-13                    # Zero 2 W -> output/images/sdcard.img
make O=../output-pi2b HOSTCC=gcc-13 HOSTCXX=g++-13   # Pi 2B   -> ../output-pi2b/images/sdcard.img
```

Kritische Regeln dabei:
- **Nie `make <board>_defconfig` auf eine bestehende `.config` anwenden** —
  setzt das gesetzte Root-Passwort auf den Platzhalter zurück.
- **HOSTCC=gcc-13 nötig**, weil GCC ≥ 14 (neuere Ubuntu) Buildroots
  gebündeltes host-m4 bricht (gnulib vs. C23-`nodiscard`;
  Fehlerbild: `gl_oset.h:275: error: expected identifier`).
- Beide Boards **niemals im selben Output-Verzeichnis** bauen
  (Cortex-A53 vs. A7 invalidiert den Toolchain) — darum `O=../output-pi2b`.
- Overlay-Änderungen (Configs/Init-Scripte) brauchen nur ein erneutes `make`
  — dauert Sekunden (target-finalize läuft immer, nichts wird kompiliert).
- Nach Abbruch einfach `make` erneut — Stamp-Dateien machen es inkrementell.

## Gelernte Lektionen (echte Hardware-Fehlersuche, Pi 2B)

1. **Kernel-Module laden nicht automatisch.** Alle Audio-/I2C-Treiber sind
   `=m` im bcm2709-Defconfig, und Buildroots mdev macht kein
   modalias-Autoload (anders als udev/RPi OS). Ohne `S02modules`
   (lädt `i2c-bcm2835`, `fixed`, `clk-hifiberry-dacpro`,
   `snd-soc-pcm512x-i2c`, `snd-soc-bcm2835-i2s`, `snd-soc-hifiberry-dacplus`)
   bleibt `aplay -l` leer — **komplett ohne dmesg-Fehler** (stilles deferred
   probe). Diagnose: `mount -t debugfs none /sys/kernel/debug;
   cat /sys/kernel/debug/devices_deferred`.
2. **LADSPA-EQ ist kaputt.** alsa-libs `type ladspa` (caps/Eq10) crasht bei
   der hw-Param-Aushandlung (`Assertion !snd_interval_empty`) — mit aplay wie
   speaker-test, auch mit `policy duplicate`. Zusätzlich: `plughw` ist selbst
   ein plug-Wrapper; **ab drei verschachtelten plug-Schichten crasht die
   Aushandlung ebenfalls** → PCMs zeigen direkt auf `hw:0,0`. Aktuell läuft
   Bypass ohne EQ. Offene Optionen: explizite Kanal-Bindings (2×Eq10) oder
   shairport-Convolution (`BR2_PACKAGE_SHAIRPORT_SYNC_CONVOLUTION`, Rebuild).
3. **Lautstärke-Konzept:** `Digital`-Regler des TAS5756 ist logarithmisch
   (−103,5…0 dB; 20 % ≈ −83 dB ≈ unhörbar — immer in dB setzen, nie Prozent).
   Treiber-Default nach Boot ist 0 dB Vollgas! `S99shairport-sync` pinnt
   **−6 dB als Hardware-Deckel**; shairport läuft ohne `mixer_control_name`
   → Software-Volume unterhalb des Deckels. (Nebenbefund: shairports
   Mixer-Attach schlägt bei Nicht-hw-`output_device` still fehl und fällt
   auf Software zurück — genau das macht den Deckel wasserdicht.)
4. **`raspberrypi2_defconfig` installiert keine DTB-Overlays** —
   `BR2_PACKAGE_RPI_FIRMWARE_INSTALL_DTB_OVERLAYS=y` musste explizit gesetzt
   werden (beim Zero-2-W-Defconfig ist es Default). Ohne das fehlt
   `hifiberry-dacplus-std.dtbo` auf der Boot-Partition.
5. **Buildroot mountet /boot nicht** — zum Inspizieren:
   `mount /dev/mmcblk0p1 /mnt/boot`.
6. **Rootfs ist beschreibbares ext4** — Live-Fixes per SSH möglich und
   reboot-fest; gehen nur beim Neuflashen verloren. Möglichst per `poweroff`
   herunterfahren (sonst ext4-Recovery beim nächsten Boot).
7. Erster Boot: Amp4 braucht eigene 12–20V-Versorgung (speist auch den Pi).
   Ohne Amp4 testbar: Boot/Netz/SSH/mDNS — aber keine Soundkarte (I2C).
   Flashen: Raspberry Pi Imager → „Use custom" → `sdcard.img`.

## Arbeitsweise mit diesem Nutzer

- Kommunikation auf **Deutsch**.
- **Commits niemals mit Claude-/AI-Selbstnennung** (kein Co-Authored-By o. ä.).
- Vor Commits kurz bestätigen lassen; **nie ungefragt pushen**.
- Nur bekannte/gepflegte Software und offizielle Pakete verwenden (Nutzer hat
  Nischen-Repos explizit abgelehnt — deshalb kein alsaequal).
- Secrets (WLAN-PSK, Root-Passwort) nie ins Repo — Platzhalter + gitignore;
  der Nutzer trägt echte Werte selbst ein.
- Der Nutzer baut auf einem Wegwerf-VPS (root), testet auf echter Hardware
  und pastet Terminal-Ausgaben hierher — Debug-Anweisungen als kurze,
  kopierbare Befehlsblöcke formulieren.

## Offene Punkte

- Software-EQ (siehe Lektion 2) — Convolution-Ansatz ist der vielversprechendste.
- Zero-2-W-Image auf echter Hardware verifizieren (S02modules & Co. sind
  bereits in dessen Overlay übernommen).
- `pcm.plugequal_fixed` heißt historisch noch so, ist aber nur noch
  plug→hw:0,0 — bei Gelegenheit umbenennen (auch in shairport-sync.conf).
