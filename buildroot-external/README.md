# buildroot-external — AirPlay-Streamer für HiFiBerry Amp4

Dies ist ein **BR2_EXTERNAL**-Tree (der offizielle Buildroot-Mechanismus für
eigene Board-Dateien außerhalb des Buildroot-Repos). Er enthält zwei
Board-Varianten:

| Board                | Defconfig                | Netzwerk                                | Hostname       |
|-----------------------|---------------------------|-------------------------------------------|----------------|
| Raspberry Pi Zero 2 W | `airplay_defconfig`       | WLAN (wpa_supplicant)                     | `airplay`      |
| Raspberry Pi 2 B      | `airplay_pi2b_defconfig`  | Ethernet (DHCP) + optionaler USB-WLAN-Stick | `airplay-pi2b` |

Beide setzen auf den jeweiligen offiziellen Buildroot-Defconfigs
(`raspberrypizero2w_defconfig` / `raspberrypi2_defconfig`) auf und ergänzen:
Paketauswahl, `config.txt`-Ergänzungen für den Amp4 und den Rootfs-Overlay
(AirPlay-Autostart, ALSA-Routing, Netzwerk).

Ausführliche Erklärung der einzelnen Phasen: siehe
`../buildroot-airplay-pi-zero2w.md` im Repo-Root (dort primär für den Zero 2 W
beschrieben). Eine Abweichung von dieser Anleitung gilt für beide Boards:
Phase 4.5 (Software-EQ) nutzt **nicht** `alsaequal` — das ist kein offizielles
Buildroot-Paket und kaum gepflegte Software. Stattdessen kommt die statische
EQ-Variante aus Anhang B zum Einsatz (`caps`/Eq10 + alsa-libs eingebautes
`type ladspa`-Plugin, feste Kurve in `asound.conf`, keine Live-Regelung per
`alsamixer -D equal`).

## Pi 2 B — Ethernet und/oder USB-WLAN

Der Pi 2 B hat keinen eingebauten WLAN-Chip. Die `airplay-pi2b`-Variante
konfiguriert deshalb **beide** Wege gleichzeitig, automatisch je nachdem was
angeschlossen ist:

- **Ethernet** (`eth0`) läuft immer per DHCP, ohne jede Konfiguration.
- **USB-WLAN-Stick** (`wlan0`): Treiber + Firmware für drei Chipsatz-Familien
  sind im Image enthalten (siehe unten). Ohne Stick eingesteckt scheitert
  `ifup wlan0` beim Boot einfach lautlos, Ethernet läuft unabhängig davon
  normal weiter.

### Unterstützte USB-WLAN-Chipsätze

| Chipsatz | Treiber | Herkunft |
|---|---|---|
| **Realtek RTL8188EU** (z. B. Edimax N150 / EW-7811Un) | `r8188eu` (Staging) | Kernel-Config-Fragment, siehe unten |
| Realtek RTL8188CUS/RTL8192CU | `rtl8xxxu` | bereits `=m` im bcm2709-Defconfig |
| Ralink/MediaTek RT2870/RT3070/RT5370 | `rt2800usb` | bereits `=m` im bcm2709-Defconfig |

Der **RTL8188EU** (Edimax N150) wird von `rtl8xxxu` *nicht* abgedeckt und ist
im bcm2709-Kernel-Defconfig nicht aktiviert — Fehlerbild:
`modprobe: FATAL: Module r8188eu not found`. Deshalb aktiviert das
Kernel-Config-Fragment `board/airplay-pi2b/linux-r8188eu.fragment`
(eingebunden über `BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES` in
`airplay_pi2b_defconfig`) den Staging-Treiber `CONFIG_R8188EU=m`. Die
zugehörige Firmware `rtlwifi/rtl8188eufw.bin` steckt bereits im ohnehin
ausgewählten `BR2_PACKAGE_LINUX_FIRMWARE_RTL_81XX` — dort ist nichts weiter
nötig.

Geladen wird `r8188eu` beim Boot explizit durch `S02modules` (Buildroots
`mdev` macht kein verlässliches modalias-Autoload, siehe den
`aplay -l`-Abschnitt unten — dasselbe Problem wie bei den Audio-Treibern).
Für die anderen beiden Chipsatz-Familien bei Bedarf analog einen
`modprobe`-Eintrag in `S02modules` ergänzen. Schnelltest auf dem Gerät:

```bash
modprobe r8188eu && ip link   # wlan0 sollte auftauchen
dmesg | tail                  # Firmware-Load + Treiber-Meldungen
```

**WLAN-Passwort später über SSH (via Ethernet) ändern:** funktioniert
problemlos, weil das Root-Dateisystem ein normales beschreibbares ext4 ist
(kein Read-only-Rootfs). Per Ethernet einloggen und:

```bash
ssh root@airplay-pi2b.local   # oder per IP
vi /etc/wpa_supplicant.conf   # ssid/psk anpassen
ifdown wlan0 && ifup wlan0    # neu verbinden, ohne Reboot
```

Die Änderung übersteht auch einen Reboot (liegt auf der beschreibbaren
Partition), geht aber bei einem **Neuflashen** der SD-Karte wieder verloren,
da das Image dann wieder aus dem gebauten `sdcard.img` (mit dem Platzhalter
aus dem Git-Repo) besteht.

## Voraussetzungen (Build-Host, Debian/Ubuntu)

```bash
sudo apt update
sudo apt install -y build-essential git bc bison flex libssl-dev \
    libncurses-dev python3 unzip rsync wget cpio file
```

~10 GB freier Plattenplatz. Mit mehr CPU-Kernen geht's deutlich schneller als
die in der Anleitung veranschlagten 30–90 Minuten (Buildroot nutzt automatisch
alle Kerne, `BR2_JLEVEL=0`).

**Drei Stolperfallen rund um Verzeichnisse** (Details und Fehlerbilder in der
[Repo-README](../README.md)):

1. Kein **Leerzeichen** irgendwo im Pfad zu Repo oder Build-Verzeichnissen —
   Buildroots make bricht damit sofort ab.
2. Build-Verzeichnisse (`buildroot/`, `output-pi2b/`) auf ein **natives
   Dateisystem** legen, nicht auf eine VM-Freigabe (virtiofs o. ä.).
3. Build-Verzeichnisse **niemals nachträglich verschieben** — absolute Pfade
   sind in die Host-Tools eingebacken.

**GCC 14+ auf dem Build-Host** (z. B. neuere Ubuntu-Versionen): `host-m4`
1.4.19 (gebündelt in Buildroot 2025.02) schlägt mit GCC 14 fehl
(`gl_oset.h:275: error: expected identifier or '(' before 'int'` — gnulib
kollidiert mit dem C23-`nodiscard`-Attribut). Falls das passiert, einen
älteren Compiler für den Host-Bootstrap installieren und explizit angeben:

```bash
sudo apt install -y gcc-13 g++-13
make host-m4-dirclean
make HOSTCC=gcc-13 HOSTCXX=g++-13   # bei jedem weiteren make-Aufruf mitgeben
```

## Build

```bash
./build.sh zero2w   # oder: ./build.sh pi2b
```

Das Skript klont Buildroot 2025.02 (falls noch nicht vorhanden als
`../buildroot`) und wendet die passende Defconfig an. **Vor dem eigentlichen
`make`** unbedingt:

1. **WLAN-Zugangsdaten** eintragen (beim Zero 2 W zwingend, beim Pi 2 B nur
   falls ein USB-WLAN-Stick genutzt werden soll):
   ```bash
   cp board/<airplay|airplay-pi2b>/rootfs-overlay/etc/wpa_supplicant.conf.example \
      board/<airplay|airplay-pi2b>/rootfs-overlay/etc/wpa_supplicant.conf
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

## Bei Build-Abbruch fortsetzen

`make` einfach erneut aufrufen — solange `output/` (bzw. der jeweilige
`O=...`-Ordner) nicht gelöscht wurde, arbeitet Buildroot inkrementell über
Stamp-Dateien weiter, kein Neustart von vorne. Vorher lohnt sich ein Blick,
*warum* abgebrochen wurde (`dmesg | grep -i "killed process"` für OOM-Kills,
sonst siehe GCC-14-Hinweis oben) — sonst läuft man direkt wieder in denselben
Fehler.

## Beide Boards parallel bauen (separates Output-Verzeichnis)

Zero 2 W und Pi 2 B **nicht** im selben `buildroot/output/` nacheinander
bauen — unterschiedliche CPU-Tuning-Flags (Cortex-A53 vs. Cortex-A7)
invalidieren beim Umschalten quasi den kompletten Cross-Toolchain-Build und
zerstören den bisherigen Fortschritt des anderen Boards. Stattdessen ein
zweites, unabhängiges Output-Verzeichnis mit `O=` nutzen — der
Quell-Download-Cache (`buildroot/dl/`, u. a. der Kernel-Tarball, der für
beide Boards identisch ist) bleibt dabei automatisch gemeinsam genutzt:

```bash
cd ../buildroot
make O=../output-pi2b BR2_EXTERNAL=../buildroot-external airplay_pi2b_defconfig
make O=../output-pi2b menuconfig   # Root-Passwort setzen, siehe oben
make O=../output-pi2b               # ggf. + HOSTCC=gcc-13 HOSTCXX=g++-13
```

Ergebnis: `../output-pi2b/images/sdcard.img` — unabhängig vom
Zero-2-W-Image in `../buildroot/output/images/sdcard.img`.

Wichtig: Ein separates `O=`-Verzeichnis teilt sich zwar die heruntergeladenen
Quellen, **nicht** aber Host-Tools/Toolchain/Kernel/Zielpakete — die werden
dort komplett neu kompiliert (kein inkrementeller Vorteil ggü. dem anderen
Board, nur der Download-Anteil entfällt).

## Auf SD-Karte schreiben & erster Boot

Siehe Phase 9/10 in `../buildroot-airplay-pi-zero2w.md` — `dd` bzw. Raspberry
Pi Imager ("Use custom"), Amp4 mit 12–20 V versorgen (Zero 2 W) bzw. Pi 2 B
per Micro-USB (Port "PWR IN") + separat Amp4 anschließen, `ssh root@<hostname>.local`,
Verifikation mit `aplay -l`, `dmesg | grep hifiberry`, `speaker-test`.

Ohne angeschlossenen Amp4 lässt sich bereits Boot/WLAN/Ethernet/SSH/mDNS
testen — `aplay -l` zeigt dann aber keine Karte, da der HiFiBerry-Codec
(TAS5756) per I2C nicht antwortet.

**`aplay -l` zeigt trotz Amp4 keine Karte** („no soundcards found"): Die
nötigen Treiber sind im RPi-Kernel alle nur Module (`=m`), und Buildroots
`mdev` lädt sie — anders als udev unter Raspberry Pi OS — nicht automatisch.
Das Init-Script `S02modules` im rootfs-overlay lädt deshalb beim Boot die
komplette Kette (`i2c-bcm2835`, `fixed`, `clk-hifiberry-dacpro`,
`snd-soc-pcm512x-i2c`, `snd-soc-bcm2835-i2s`, `snd-soc-hifiberry-dacplus`).
Fehlt eins davon, hängen die Treiber **stumm** in deferred probe (nichts in
`dmesg`!) — diagnostizierbar über:

```bash
mount -t debugfs none /sys/kernel/debug
cat /sys/kernel/debug/devices_deferred   # zeigt wartende Geräte + Grund
```

## Per SSH verbinden

```bash
ssh root@airplay.local        # Zero 2 W
ssh root@airplay-pi2b.local   # Pi 2 B
```

Nutzt mDNS/Bonjour über `avahi` — funktioniert out of the box auf
macOS/Linux, unter Windows braucht es eine Bonjour-Installation (z. B. über
iTunes). Login mit `root` + dem gesetzten `BR2_TARGET_GENERIC_ROOT_PASSWD`.

Falls `.local` nicht auflöst, IP-Adresse suchen (DHCP-Client-Liste des
Routers, oder `nmap -sn <netzbereich>` / `avahi-browse -a`) und direkt per
`ssh root@<ip>` verbinden.

## Lautstärke: fester Hardware-Deckel + Software-Volume

`S99shairport-sync` setzt beim Boot den Hardware-Regler `Digital` des
TAS5756 fest auf **−6 dB**. In `shairport-sync.conf` ist bewusst **kein**
`mixer_control_name` gesetzt — shairport regelt die AirPlay-Lautstärke rein
in Software *unterhalb* dieses Deckels. Volle iPhone-Lautstärke kann damit
nie lauter werden als der gesetzte Wert (Schutz der Lautsprecher).

Deckel ändern: dB-Wert in `S99shairport-sync` anpassen (`amixer -c 0 sset
Digital -- -6dB`). Achtung: Der Regler arbeitet logarithmisch über eine
Spanne von −103,5…0 dB — Prozentangaben in `amixer` täuschen (20 % ≈ −83 dB
≈ unhörbar), immer direkt in dB setzen. Ohne den Init-Eintrag startet der
Treiber mit 0 dB (Vollgas).

## Software-EQ: derzeit deaktiviert (Bypass)

Die statische EQ-Variante aus Anhang B (`caps`/Eq10 über alsa-libs
`type ladspa`-Plugin) ist mit alsa-lib 1.2.x **defekt**: Die
hw-Parameter-Aushandlung über der LADSPA-Schicht bricht mit
`Assertion !snd_interval_empty(i) failed` ab (auf echter Hardware
verifiziert; auch mit `policy duplicate`, unabhängig vom Player — aplay wie
speaker-test). Zusätzliche Stolperfalle dabei: `plughw:0,0` ist selbst schon
ein plug-Wrapper — ab drei verschachtelten plug-Schichten scheitert die
Aushandlung ebenfalls, daher verweisen die PCMs in `asound.conf` direkt auf
`hw:0,0`.

Die Audiokette läuft deshalb aktuell im Bypass (`shairport-sync → plug →
hw:0,0`). Kandidaten für eine spätere EQ-Lösung:

1. `type ladspa` mit expliziten Kanal-Bindings (zwei Eq10-Instanzen, je
   Kanal fest verdrahtet) statt `policy duplicate` — ungetestet.
2. shairport-syncs eingebauter **Convolution-Filter** (FIR über
   Impulsantwort-Datei, `BR2_PACKAGE_SHAIRPORT_SYNC_CONVOLUTION`) — kann
   beliebige EQ-Kurven abbilden und ist gepflegter Code; braucht einen
   Rebuild und ein Werkzeug zum Erzeugen der Impulsantwort aus der
   Wunschkurve.
