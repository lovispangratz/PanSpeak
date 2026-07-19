# PanSpeak

Minimales Linux-Buildroot-System für den Raspberry Pi Zero 2 W + HiFiBerry
Amp4 mit Support für AirPlay 1.
Zweite Board-Variante: Raspberry Pi 2 B (Ethernet + optionaler USB-WLAN-Stick,
z. B. Edimax N150).

Detail-Doku (Board-Varianten, WLAN-Chipsätze, Troubleshooting auf dem Gerät):
[`buildroot-external/README.md`](buildroot-external/README.md) —
ursprüngliche Anleitung: [`buildroot-airplay-pi-zero2w.md`](buildroot-airplay-pi-zero2w.md)

## Schnellstart auf einem frischen Ubuntu-Build-Host (z. B. Wegwerf-VPS)

```bash
git clone <dieses-repo> PanSpeak && cd PanSpeak
./setup-vps.sh
```

Das Script installiert alle Host-Pakete (inkl. `gcc-13`), klont Buildroot
und legt die Konfigurationen für beide Boards an. Danach den Anweisungen am
Script-Ende folgen (Secrets eintragen, dann bauen). Es setzt voraus, dass
das Repo auf einer normalen lokalen Platte liegt — falls nicht (z. B.
VM-Freigabe), siehe Schritt 1 der manuellen Anleitung.

## Manuell bauen, Schritt für Schritt

### 1. Wo Repo und Build-Verzeichnisse liegen dürfen

Drei harte Regeln, alle aus echten Fehlschlägen gelernt:

- **Kein Leerzeichen im Pfad.** Buildroots make-System bricht sonst sofort
  mit `make[1]: *** /pfad/bis/zum/leerzeichen: No such file or directory` ab.
  Symlinks helfen nicht (make löst sie physisch auf) — den Ordner selbst
  umbenennen.
- **Build-Verzeichnisse auf ein natives Dateisystem** (ext4 & Co.), nicht
  auf eine VM-/Netzwerk-Freigabe (virtiofs, NFS, 9p, SMB). Auf Freigaben
  verlieren generierte Skripte ihr Exec-Bit — Fehlerbild:
  `host/bin/pkg-config: Permission denied` mitten im Build. Das *Repo*
  selbst darf auf der Freigabe liegen, nur `buildroot/` und `output-pi2b/`
  nicht.
- **Build-Verzeichnisse niemals nachträglich verschieben.** Absolute Pfade
  (RPATH, `--prefix`) sind in die gebauten Host-Tools eingebacken; nach
  einem `mv` schlagen Bibliotheks-Lookups fehl
  (`error while loading shared libraries` / RPATH-Check-Fehler). Falls doch
  passiert: `.config` sichern, Verzeichnis komplett leeren, `.config`
  zurücklegen, neu bauen.

Die Anleitung unten benutzt zwei Variablen — anpassen und in jeder neuen
Shell erneut setzen:

```bash
REPO=~/PanSpeak     # geklontes Repo (darf auf einer Freigabe liegen)
BUILD=~/build       # nativ + leerzeichenfrei; nimmt buildroot/ + output-pi2b/ auf
```

Liegt das Repo auf einer normalen lokalen Platte, geht auch das klassische
Layout aus `setup-vps.sh` (Buildroot als `$REPO/buildroot`, Pi-2B-Output als
`$REPO/output-pi2b` — beide gitignored); dann überall `$BUILD` durch `$REPO`
ersetzen.

### 2. Host-Pakete installieren (Debian/Ubuntu)

```bash
sudo apt update
sudo apt install -y build-essential git bc bison flex libssl-dev \
    libncurses-dev python3 unzip rsync wget cpio file gcc-13 g++-13
```

`gcc-13` ist Pflicht auf neueren Ubuntu-Versionen: deren GCC 14/15 bricht
Buildroots gebündeltes `host-m4` (gnulib vs. C23-`nodiscard`, Fehlerbild
`gl_oset.h:275: error: expected identifier`). Deshalb unten überall
`HOSTCC=gcc-13 HOSTCXX=g++-13`.

### 3. Buildroot klonen und Konfigurationen anlegen

```bash
mkdir -p "$BUILD"
git clone --depth 1 --branch 2025.02 \
    https://gitlab.com/buildroot.org/buildroot.git "$BUILD/buildroot"
cd "$BUILD/buildroot"

# Zero 2 W (baut in ./output):
make BR2_EXTERNAL="$REPO/buildroot-external" airplay_defconfig

# Pi 2 B (eigenes Output-Verzeichnis - NIE beide Boards im selben bauen,
# Cortex-A53 vs. A7 invalidiert sonst den kompletten Toolchain):
make O="$BUILD/output-pi2b" BR2_EXTERNAL="$REPO/buildroot-external" \
    airplay_pi2b_defconfig
```

**Achtung:** `make <board>_defconfig` nur dieses eine Mal ausführen. Ein
erneutes Anwenden setzt die `.config` zurück — inklusive des im nächsten
Schritt gesetzten Root-Passworts (wieder Platzhalter!).

### 4. Secrets eintragen (einmalig, niemals committen)

**WLAN-Zugangsdaten** (Zero 2 W zwingend; Pi 2 B nur falls USB-WLAN-Stick):

```bash
cd "$REPO/buildroot-external"
cp board/airplay/rootfs-overlay/etc/wpa_supplicant.conf.example \
   board/airplay/rootfs-overlay/etc/wpa_supplicant.conf        # Zero 2 W
cp board/airplay-pi2b/rootfs-overlay/etc/wpa_supplicant.conf.example \
   board/airplay-pi2b/rootfs-overlay/etc/wpa_supplicant.conf   # Pi 2 B
# dann jeweils ssid/psk eintragen - die Dateien sind gitignored
```

**Root-Passwort** (je Board eigene `.config`, sonst verweigert SSH den Login):

```bash
cd "$BUILD/buildroot"
make menuconfig                        # Zero 2 W
make O="$BUILD/output-pi2b" menuconfig # Pi 2 B
# -> System configuration -> Root password
```

### 5. Bauen

```bash
cd "$BUILD/buildroot"
make HOSTCC=gcc-13 HOSTCXX=g++-13                          # Zero 2 W
make O="$BUILD/output-pi2b" HOSTCC=gcc-13 HOSTCXX=g++-13   # Pi 2 B
```

Dauer: 1–2 h beim ersten Mal (nutzt automatisch alle Kerne), ~10 GB
Plattenplatz. Nach einem Abbruch einfach dasselbe `make` erneut aufrufen —
Buildroot arbeitet über Stamp-Dateien inkrementell weiter. Änderungen nur am
Rootfs-Overlay (Configs, Init-Scripte) brauchen ebenfalls nur ein erneutes
`make` und sind in Sekunden eingepflegt.

Ergebnisse:

| Board | Image |
|---|---|
| Zero 2 W | `$BUILD/buildroot/output/images/sdcard.img` |
| Pi 2 B | `$BUILD/output-pi2b/images/sdcard.img` |

### 6. Flashen & erster Boot

`sdcard.img` mit dem Raspberry Pi Imager („Use custom") oder `dd` auf die
SD-Karte schreiben. Amp4 braucht eine eigene 12–20-V-Versorgung (speist auch
den Pi). Danach:

```bash
ssh root@airplay.local        # Zero 2 W
ssh root@airplay-pi2b.local   # Pi 2 B
```

Verifikation, Sound-Debugging (stilles deferred probe!), WLAN-Sticks und
Lautstärke-Konzept: siehe
[`buildroot-external/README.md`](buildroot-external/README.md).
