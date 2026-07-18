# PanSpeak
Minimales Linux-BuildRoot-System für den RaspberryPi Zero 2 W + HifiBerry Amp4 mit Support für AirPlay 1.
Zweite Board-Variante: Raspberry Pi 2 B (Ethernet + optionaler USB-WLAN-Stick).

## Schnellstart auf einem frischen Ubuntu-Build-Host (z. B. Wegwerf-VPS)

```bash
git clone <dieses-repo> PanSpeak && cd PanSpeak
./setup-vps.sh
```

Das Script installiert alle Host-Pakete (inkl. `gcc-13` — neuere
Ubuntu-Versionen liefern GCC 14/15, womit Buildroot 2025.02s `host-m4`
nicht baut), klont Buildroot und legt die Konfigurationen für beide Boards
an. Danach den Anweisungen am Script-Ende folgen (WLAN-Zugangsdaten +
Root-Passwörter eintragen, dann bauen).

Details: [`buildroot-external/README.md`](buildroot-external/README.md) —
Anleitung: [`buildroot-airplay-pi-zero2w.md`](buildroot-airplay-pi-zero2w.md)
