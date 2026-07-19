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
  (Wegwerf-VPS-Workflow). Inzwischen baut der Nutzer alternativ in einer
  lokalen VM, deren Repo auf einer virtiofs-Freigabe liegt — dann liegen die
  Build-Verzeichnisse **außerhalb** des Repos nativ in der VM (aktuell
  `/root/build/{buildroot,output-pi2b}`), siehe Lektion 8.
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
- Pfade: kein Leerzeichen, kein virtiofs für Build-Verzeichnisse, Output nie
  verschieben — Details in Lektion 8 und der Repo-README.

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
8. **Build-Host-Verzeichnisse (VM-Setup, Juli 2026):** Drei Fallen in einer
   Session gefunden: (a) **Leerzeichen im Pfad** → Buildroots make bricht
   sofort ab (`make[1]: *** /pfad/bis/leerzeichen: No such file or
   directory`); Symlink hilft nicht, make löst physisch auf — Ordner auf dem
   Host umbenennen. (b) **virtiofs-Freigaben taugen nicht als
   Build-Verzeichnis**: generierte Skripte verlieren das Exec-Bit
   (`host/bin/pkg-config: Permission denied`) — `buildroot/` + `output-*/`
   nativ ablegen (`/root/build/`), nur das Repo darf auf der Freigabe
   liegen. (c) **Output-Verzeichnisse sind nicht verschiebbar** (RPATH/
   `--prefix` absolut eingebacken; Fehlerbild `libpkgconf.so.5: cannot open`
   bzw. „installs executables without proper RPATH") — nach einem `mv`:
   `.config` sichern, Rest wegwerfen, neu bauen (`BR2_EXTERNAL` beim ersten
   make wieder mitgeben, `.br2-external.mk` ist dann weg).
9. **Edimax N150: `modprobe r8188eu` schlägt fehl, weil es den
   Staging-Treiber seit Kernel 6.3 nicht mehr gibt** — RTL8188EU-Support
   ist in `rtl8xxxu` gewandert (bereits `=m` im bcm2709-Defconfig).
   Achtung doppelt: (a) Netz-Anleitungen mit r8188eu sind für ≥6.3 alle
   veraltet; (b) das Kernel-Fragment-Merge (`merge_config.sh`) verwirft
   unbekannte Symbole **stillschweigend** — nach jedem Fragment-Build im
   fertigen `.config` gegenprüfen! Einige Geräte-IDs (u. a. Edimax N150 V1,
   RTL8188CUS `7392:7811`) sind hinter `RTL8XXXU_UNTESTED` versteckt → das
   schaltet `board/airplay-pi2b/linux-usb-wifi.fragment` frei
   (`BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES`); der V2 (RTL8188EU
   `7392:b811`) steht in der Haupttabelle. Firmware beider Varianten ist in
   `BR2_PACKAGE_LINUX_FIRMWARE_RTL_81XX` enthalten. Geladen wird `rtl8xxxu`
   per `S02modules` (siehe Lektion 1 — ohne Stick harmlos). Stand: gebaut,
   auf Hardware noch ungetestet.

## Arbeitsweise mit diesem Nutzer

- Kommunikation auf **Deutsch**.
- **Commits niemals mit Claude-/AI-Selbstnennung** (kein Co-Authored-By o. ä.).
- Vor Commits kurz bestätigen lassen; **nie ungefragt pushen**.
- Nur bekannte/gepflegte Software und offizielle Pakete verwenden (Nutzer hat
  Nischen-Repos explizit abgelehnt — deshalb kein alsaequal).
- Secrets (WLAN-PSK, Root-Passwort) nie ins Repo — Platzhalter + gitignore;
  der Nutzer trägt echte Werte selbst ein.
- Der Nutzer baut als root auf einem Wegwerf-VPS oder einer lokalen VM
  (Repo auf virtiofs-Freigabe, Build-Verzeichnisse nativ — Lektion 8),
  testet auf echter Hardware und pastet Terminal-Ausgaben hierher —
  Debug-Anweisungen als kurze, kopierbare Befehlsblöcke formulieren.
- Beim Inspizieren von `.config`-Dateien aufpassen: dort steht das echte
  Root-Passwort im Klartext (`BR2_TARGET_GENERIC_ROOT_PASSWD`) — nie breit
  grep-en/catten, nur gezielt die benötigte Variable.

## Offene Punkte

- Edimax N150 / rtl8xxxu (Lektion 9) auf echter Hardware testen:
  `ip link` sollte `wlan0` zeigen, `dmesg` Geräte-Erkennung + Firmware-Load.
- Software-EQ (siehe Lektion 2) — Convolution-Ansatz ist der vielversprechendste.
- Zero-2-W-Image auf echter Hardware verifizieren (S02modules & Co. sind
  bereits in dessen Overlay übernommen).
- `pcm.plugequal_fixed` heißt historisch noch so, ist aber nur noch
  plug→hw:0,0 — bei Gelegenheit umbenennen (auch in shairport-sync.conf).
