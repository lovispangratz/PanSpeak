# Buildroot: Minimaler AirPlay-1-Streamer
## Raspberry Pi Zero 2 W + HiFiBerry Amp4 + Software-EQ

Diese Anleitung baut ein schlankes, von Grund auf konfiguriertes Linux-Image, das
beim Booten automatisch einen AirPlay-1-Empfänger (shairport-sync) startet, das
Audio über einen Software-Equalizer (alsaequal/CAPS) leitet und an das HiFiBerry
Amp4 ausgibt. WLAN und SSH sind eingerichtet, sodass das Gerät headless läuft.

**Zielbild der Signalkette:**

```
iPhone (Spotify) --AirPlay 1--> shairport-sync --ALSA "default"--> plug --> equal (EQ) --> plughw:0,0 --> HiFiBerry Amp4 (TAS5756) --> Lautsprecher
```

> **Board-Hinweis:** Die Anleitung ist für den **Amp4** geschrieben (Overlay
> `hifiberry-dacplus-std`). Für **Amp2** gilt dasselbe Overlay. Für den **Amp4 Pro**
> brauchst du `hifiberry-amp4pro` und einen Kernel ≥ 6.1.77 — siehe Anhang A.

---

## Phase 0 — Voraussetzungen (Build-Host)

Ein Linux-Host (nativ oder VM). Buildroot baut **nicht** sauber auf macOS — falls du
auf dem Mac arbeitest, nimm eine Linux-VM (z. B. Debian/Fedora in UTM).

Benötigte Host-Pakete (Debian/Ubuntu-Beispiel):

```bash
sudo apt update
sudo apt install -y build-essential git bc bison flex libssl-dev \
    libncurses-dev python3 unzip rsync wget cpio file
```

Plane **30–90 Minuten** für den ersten Build ein (Toolchain wird komplett gebaut)
und ~10 GB freien Plattenplatz.

---

## Phase 1 — Buildroot holen

Nutze einen stabilen LTS-Release-Tag, nicht `master` (reproduzierbarer):

```bash
git clone https://gitlab.com/buildroot.org/buildroot.git
cd buildroot
# Aktuellen LTS-Tag wählen (Beispiel — prüfe https://buildroot.org/download.html):
git checkout 2025.02
```

> Falls der gewählte LTS-Release den gepinnten RPi-Kernel zu alt mitbringt
> (Overlay `hifiberry-dacplus-std` fehlt), siehe Phase 5 / Troubleshooting.

---

## Phase 2 — Basis-Defconfig

Es gibt eine fertige 32-Bit-Konfiguration für genau dieses Board. 32-Bit ist für
einen Audio-Streamer ausreichend und schont den knappen RAM (512 MB) des Zero 2 W.

```bash
make raspberrypizero2w_defconfig
```

Diese Konfiguration bringt bereits mit: RPi-Firmware, passender Kernel
(`bcm2709`-Defconfig, DTS `bcm2710-rpi-zero-2-w`), ext4-Rootfs und das
Post-Image-Script, das am Ende ein fertiges `sdcard.img` erzeugt.

---

## Phase 3 — Eigenes Board-Verzeichnis für deine Anpassungen

Damit deine Config-Dateien sauber außerhalb des Buildroot-Baums liegen, legst du
ein Overlay-Verzeichnis an. Alles darunter wird 1:1 ins Root-Dateisystem kopiert.

```bash
mkdir -p board/airplay/rootfs-overlay/etc/init.d
mkdir -p board/airplay/rootfs-overlay/etc/network
```

Die einzelnen Dateien füllst du in **Phase 7**.

---

## Phase 4 — Paketauswahl (`make menuconfig`)

```bash
make menuconfig
```

Setze die folgenden Optionen. In Klammern jeweils der Menüpfad bzw. das
Config-Symbol.

### 4.1 System-Grundeinstellungen
- **System configuration → System hostname** → z. B. `airplay`
- **System configuration → Root password** → ein Passwort setzen
  (sonst verweigert SSH den Root-Login!)
- **System configuration → Path to the users tables / rootfs overlay directories**
  → bei **Root filesystem overlay directories** (`BR2_ROOTFS_OVERLAY`) eintragen:
  ```
  board/airplay/rootfs-overlay
  ```

### 4.2 AirPlay-Empfänger
- **Target packages → Audio and video applications → shairport-sync**
  (`BR2_PACKAGE_SHAIRPORT_SYNC=y`)
  - Unteroption **soxr support** aktivieren (bessere Resampling-Qualität)
  - (optional) **convolution support** — nur falls du später FIR-Faltung direkt in
    shairport nutzen willst; für unseren EQ nicht nötig

  > Buildroots shairport-sync-Paket ist **nur Classic AirPlay 1** — genau das, was
  > wir wollen. Es zieht automatisch `alsa-lib`, `libconfig`, `openssl` und `popt`.

### 4.3 mDNS (Bonjour-Discovery — damit das iPhone das Gerät findet)
- **Target packages → Networking applications → avahi**
  (`BR2_PACKAGE_AVAHI=y`)
  - **avahi-daemon** aktivieren (`BR2_PACKAGE_AVAHI_DAEMON=y`)
  - Das zieht `dbus` mit herein (`BR2_PACKAGE_DBUS=y`) — bestätigen.

### 4.4 ALSA-Werkzeuge
- **Target packages → Audio and video applications → alsa-utils**
  (`BR2_PACKAGE_ALSA_UTILS=y`)
  - Mindestens aktivieren: `aplay/arecord`, `amixer`, `alsamixer`, `alsactl`,
    `speaker-test` (zum Testen und EQ-Tunen)

### 4.5 Software-EQ
- **Target packages → Audio and video applications → alsaequal**
  (`BR2_PACKAGE_ALSAEQUAL=y`)
  - Zieht automatisch `caps` (die CAPS-LADSPA-Plugins inkl. `Eq10`) und `alsa-lib`.
- (optional) **alsa-plugins** (`BR2_PACKAGE_ALSA_PLUGINS=y`) — nur nötig, falls du
  statt der live-regelbaren `type equal`-Variante die statische `type ladspa`-Variante
  nutzen willst (siehe Anhang B).

### 4.6 WLAN
- **Target packages → Networking applications → wpa_supplicant**
  (`BR2_PACKAGE_WPA_SUPPLICANT=y`)
  - **Enable nl80211 support** aktivieren
  - **Install wpa_cli / wpa_passphrase** aktivieren (praktisch zum Debuggen)
- **Target packages → Hardware handling → Firmware → linux-firmware**
  (`BR2_PACKAGE_LINUX_FIRMWARE=y`)
  - Unter **WiFi firmware** die **Broadcom BCM43xxx** wählen
    (`BR2_PACKAGE_LINUX_FIRMWARE_BRCM_BCM43XXX=y`)

  > Die WLAN-Firmware des Zero 2 W (Chip CYW43436/43430) ist der häufigste
  > Stolperstein. Nach dem ersten Boot mit `dmesg | grep brcmfmac` prüfen, ob die
  > Firmware geladen wurde. Falls nicht: siehe Troubleshooting.

### 4.7 SSH (headless-Verwaltung, EQ-Tuning)
- **Target packages → Networking applications → dropbear**
  (`BR2_PACKAGE_DROPBEAR=y`)

### 4.8 Kernel — Device-Tree-Overlays
- **Kernel → Build a Device Tree Blob (DTB)** ist durch das Defconfig bereits aktiv.
- Zusätzlich **Device tree blob overlay support** aktivieren
  (`BR2_LINUX_KERNEL_DTB_OVERLAY_SUPPORT=y`), damit die Overlays gebaut werden.

Speichern und `menuconfig` verlassen.

---

## Phase 5 — Device-Tree-Overlay sicherstellen

Das HiFiBerry-Overlay muss als `.dtbo` auf der FAT-Boot-Partition unter `overlays/`
landen. In der Regel liefert das `rpi-firmware`-Paket bereits **alle** RPi-Overlays
(inkl. der HiFiBerry-Dateien) mit — du musst nichts extra bauen. Wir verifizieren
das aber nach dem Build (Phase 10).

Der Kernel braucht zudem den passenden Codec-Treiber (TAS571x / HiFiBerry). Der
`bcm2709`-RPi-Kernel enthält diese als Module — out of the box vorhanden.

> **Kernel zu alt?** `hifiberry-dacplus-std` existiert erst ab Kernel 6.1.77. Auf
> dem Zero 2 W (kein Pi5) funktioniert als Fallback auch das ältere Overlay
> `hifiberry-dacplus`. Nutze dieses in Phase 6, falls `-std` fehlt.

---

## Phase 6 — config.txt anpassen

Das Defconfig verweist auf die Boot-Config-Datei
`board/raspberrypizero2w/config_zero2w.txt`. Öffne sie und **ergänze am Ende**:

```ini
# --- HiFiBerry Amp4 ---
# Internes BCM-Audio deaktivieren:
dtparam=audio=off
# HiFiBerry-Treiber laden (Amp4 / Amp2):
dtoverlay=hifiberry-dacplus-std

# --- Debug-Konsole über UART (optional, sehr empfehlenswert beim ersten Boot) ---
enable_uart=1
```

> Die vorhandenen Zeilen (Kernel-Name etc.) **nicht** löschen, nur anhängen.
>
> Für **Amp4 Pro** stattdessen `dtoverlay=hifiberry-amp4pro` (Anhang A).

---

## Phase 7 — Dateien im rootfs-overlay anlegen

Alle Pfade relativ zu `board/airplay/rootfs-overlay/`.

### 7.1 `etc/asound.conf` — ALSA-Routing durch den EQ

```
# Steuer-Element für live-Regelung via "alsamixer -D equal"
ctl.equal {
    type equal
    controls "/etc/alsaequal.bin"
}

# EQ-Stufe, gibt an die HiFiBerry-Karte (card 0) aus
pcm.plugequal {
    type equal
    slave.pcm "plughw:0,0"
    controls "/etc/alsaequal.bin"
}

# Standard-Ausgabe läuft durch einen Format-Konverter (plug) in den EQ.
# alsaequal arbeitet intern mit Float, "plug" sorgt für die Konvertierung.
pcm.!default {
    type plug
    slave.pcm "plugequal"
}
```

### 7.2 `etc/shairport-sync.conf` — AirPlay-Empfänger

```
general = {
    name = "Wohnzimmer";          // so erscheint das Gerät im AirPlay-Menü
    interpolation = "soxr";       // braucht die in 4.2 aktivierte soxr-Option
};

alsa = {
    output_device = "plugequal";  // explizit durch den EQ
    // Hardware-Lautstärke des TAS5756 nutzen (optional, bessere Qualität als
    // reine Software-Dämpfung). Kontrollnamen nach dem Boot mit
    // "amixer -c 0 scontrols" verifizieren — oft "Digital".
    mixer_control_name = "Digital";
};
```

### 7.3 `etc/init.d/S99shairport-sync` — Autostart

```sh
#!/bin/sh
#
# Startet shairport-sync nach dbus (S30) und avahi (S50).
#
DAEMON=/usr/bin/shairport-sync
PIDFILE=/var/run/shairport-sync.pid
CONF=/etc/shairport-sync.conf

case "$1" in
    start)
        printf "Starting shairport-sync: "
        start-stop-daemon -S -b -m -p "$PIDFILE" \
            -x "$DAEMON" -- -c "$CONF"
        echo "OK"
        ;;
    stop)
        printf "Stopping shairport-sync: "
        start-stop-daemon -K -q -p "$PIDFILE"
        echo "OK"
        ;;
    restart|reload)
        "$0" stop
        sleep 1
        "$0" start
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac
exit 0
```

Ausführbar machen (auf dem Build-Host):

```bash
chmod +x board/airplay/rootfs-overlay/etc/init.d/S99shairport-sync
```

### 7.4 `etc/network/interfaces` — Netzwerk

```
auto lo
iface lo inet loopback

auto wlan0
iface wlan0 inet dhcp
    pre-up wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant.conf -D nl80211
    post-down killall -q wpa_supplicant
```

### 7.5 `etc/wpa_supplicant.conf` — WLAN-Zugang

```
ctrl_interface=/var/run/wpa_supplicant
update_config=1
country=DE

network={
    ssid="DEIN_WLAN_NAME"
    psk="DEIN_WLAN_PASSWORT"
}
```

> Tipp: Statt Klartext-PSK kannst du auf dem Host
> `wpa_passphrase "SSID" "Passwort"` ausführen und den gehashten Block einsetzen.

---

## Phase 8 — Bauen

```bash
make
```

Beim ersten Mal dauert das eine Weile. Das fertige Image liegt anschließend unter:

```
output/images/sdcard.img
```

---

## Phase 9 — Auf SD-Karte schreiben

`/dev/sdX` durch dein echtes Gerät ersetzen (mit `lsblk` prüfen — **Vorsicht, das
überschreibt die Karte vollständig!**):

```bash
sudo dd if=output/images/sdcard.img of=/dev/sdX bs=4M conv=fsync status=progress
sync
```

Alternativ Raspberry Pi Imager / balenaEtcher mit der `sdcard.img` verwenden.

---

## Phase 10 — Erster Boot & Verifikation

SD-Karte einlegen, Amp4 mit 12–20 V versorgen (das speist auch den Pi), booten.

Nach ~30–60 s sollte „Wohnzimmer" im AirPlay-Menü des iPhones auftauchen. Per SSH
einloggen (`ssh root@airplay.local` oder über die IP) und der Reihe nach prüfen:

```bash
# 1) WLAN-Firmware geladen?
dmesg | grep brcmfmac

# 2) Soundkarte erkannt? (HiFiBerry sollte als card 0 erscheinen)
aplay -l

# 3) Overlay tatsächlich aktiv?
dmesg | grep -i hifiberry

# 4) Direkter Hardware-Test (umgeht den EQ):
speaker-test -D plughw:0,0 -c 2 -t wav

# 5) Test durch die EQ-Kette:
speaker-test -D default -c 2 -t wav

# 6) Läuft der AirPlay-Dienst?
ps | grep shairport-sync
```

Wenn 1–6 sauber durchlaufen, von Spotify auf dem iPhone AirPlay → „Wohnzimmer"
wählen und abspielen.

### EQ einstellen

```bash
alsamixer -D equal
```

Zeigt die 10 Bänder (31 Hz … 16 kHz), die du live anhebst/absenkst. Die Werte
werden in `/etc/alsaequal.bin` gespeichert und bleiben über Reboots erhalten.

> **Headroom-Hinweis:** Beim Anheben von Bändern kannst du digital clippen. Senke
> im Zweifel die Gesamtlautstärke etwas ab oder arbeite eher mit Absenkungen statt
> Anhebungen.

---

## Troubleshooting

**„Wohnzimmer" erscheint nicht im AirPlay-Menü**
- avahi/dbus laufen? `ps | grep -E "avahi|dbus"`. Falls nicht, Init-Scripte prüfen
  (`ls /etc/init.d/`); ggf. avahi/dbus manuell starten und Reihenfolge kontrollieren.
- iPhone und Pi im selben Netz/Subnetz? mDNS/Multicast darf nicht geblockt sein.

**Kein Ton, `aplay -l` zeigt keine Karte**
- Overlay fehlt: Prüfe auf der FAT-Boot-Partition, ob
  `overlays/hifiberry-dacplus-std.dtbo` existiert. Falls nicht, entweder
  `hifiberry-dacplus` in der config.txt verwenden (Zero-2-W-tauglich) oder die
  `.dtbo` aus `output/build/linux-*/arch/arm/boot/dts/overlays/` manuell in die
  Boot-Partition kopieren.
- `dtparam=audio=off` gesetzt? Sonst belegt das BCM-Audio die Ressourcen.

**WLAN verbindet nicht**
- `dmesg | grep brcmfmac` zeigt fehlende Firmware → die korrekte
  `brcmfmac43436*`-Firmware + NVRAM (`.txt`) für den Zero 2 W fehlt. Diese
  stammen teils aus dem RPi-Firmware-Repo; ggf. die passenden Dateien nach
  `/lib/firmware/brcm/` ergänzen (per rootfs-overlay) und neu bauen.
- `wpa_supplicant`-Logs: `wpa_supplicant -i wlan0 -c /etc/wpa_supplicant.conf -d`

**AirPlay-Aussetzer**
- WLAN-Powersave abschalten: `iw dev wlan0 set power_save off` (z. B. in einem
  Boot-Script). Der Zero 2 W neigt sonst zu Verbindungsabbrüchen im Idle.

---

## Anhang A — Abweichungen für andere Boards

| Board     | config.txt-Overlay              | Kernel-Anforderung      |
|-----------|----------------------------------|-------------------------|
| Amp2      | `dtoverlay=hifiberry-dacplus-std` | unkritisch (Fallback: `hifiberry-dacplus`) |
| Amp4      | `dtoverlay=hifiberry-dacplus-std` | unkritisch (Fallback: `hifiberry-dacplus`) |
| Amp4 Pro  | `dtoverlay=hifiberry-amp4pro`     | **Kernel ≥ 6.1.77**, `hifiberry-amp4pro.dtbo` muss existieren |

Beim Amp4 Pro nach dem Build unbedingt prüfen, dass `hifiberry-amp4pro.dtbo` auf der
Boot-Partition liegt — fehlt sie, ist der mitgelieferte Kernel/Firmware-Stand zu alt.

---

## Anhang B — Statischer EQ (Alternative ohne Live-Regelung)

Wenn du feste EQ-Kurven ohne `alsamixer` willst, brauchst du `alsa-plugins`
(Phase 4.5) und ersetzt in `asound.conf` die `plugequal`-Definition durch eine
`type ladspa`-Stufe mit fest verdrahteten Werten (Bänder: 31, 63, 125, 250, 500,
1k, 2k, 4k, 8k, 16k Hz):

```
pcm.plugequal_fixed {
    type plug
    slave.pcm "plughw:0,0"
}

pcm.equal_fixed {
    type ladspa
    slave.pcm plugequal_fixed
    path "/usr/lib/ladspa"
    plugins [{
        label Eq10
        input {
            # dB pro Band:
            controls [ -3 -2 0 0 1 1 0 0 2 3 ]
        }
    }]
}

pcm.!default {
    type plug
    slave.pcm "equal_fixed"
}
```

---

## Anhang C — Späterer Umstieg auf AirPlay 2

Buildroots shairport-sync-Paket kann **kein** AirPlay 2. Dafür müsstest du:
1. shairport-sync mit `--with-airplay-2` bauen (eigenes Package/Patch),
2. den Begleit-Daemon **nqptp** als eigenes Buildroot-Package ergänzen,
3. `ffmpeg` (mit AAC-Decoder), `libplist`, `libsodium`, `libgcrypt` hinzunehmen,
4. die Ports 319/320 für nqptp freihalten.

Das ist deutlich aufwändiger und braucht mehr CPU/RAM. Für Spotify-Streaming bringt
es klanglich nichts gegenüber AirPlay 1 — nur relevant, wenn du echtes
Multiroom-Sync über mehrere Lautsprecher willst.
