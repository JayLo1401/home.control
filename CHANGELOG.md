# Changelog

Alle nennenswerten Änderungen je Version. Format angelehnt an [Keep a Changelog](https://keepachangelog.com/de/1.1.0/), Versionsnummern nach [Semantic Versioning](https://semver.org/lang/de/).

## [1.0.0] – 2026-10-15

Erste veröffentlichte Version, unter der Lizenz [PolyForm Noncommercial 1.0.0](LICENSE.md) – frei für private und nicht-kommerzielle Nutzung, kommerzielle Nutzung nicht erlaubt.

### Panels

- Schnellzugriffs-Panel über jedem laufenden Bild (Film, Spotify, Radio …), geöffnet per angelernter Fernbedienungstaste; das Video läuft weiter.
- Mehrere Panels mit eigener Taste; Bedienung mit Pfeiltasten, OK schaltet, Zurück schließt.
- Gruppen als Überschrift mit Kacheln darunter; Temperatur, Luftfeuchte und Stromverbrauch (W) in der Überschrift.
- Flache Kacheln, Zustand über Farbe; Sensoren zeigen ihren Wert, Zahlen mit deutschem Komma.
- Eigene Namen und Symbole je Entität, Symbole aus Home Assistant (`mdi:…`) werden übernommen; Symbolauswahl mit Suche in allen Material Design Icons.
- Spaltenzahl, Panelgröße und automatisches Schließen einstellbar.

### Lang drücken

- Dieselbe Taste: kurz öffnet das Panel, lang löst eine Aktion aus (Umschalten, Ein, Aus).
- Halte-Popup mit Fortschrittsring; Loslassen vor Ablauf bricht ab.

### Türglocke

- Anmeldung als Gerät der Home-Assistant-Integration `mobile_app`; eigener Dienst `notify.mobile_app_<gerätename>`.
- Nachrichten lokal über den WebSocket-Push-Kanal, keine Cloud nötig.
- Meldung über allem mit Glocke, Text, Uhrzeit und optionalem Kamerabild; bleibt 30 Sekunden (einstellbar).
- Gong mit Audio-Ducking: laufende Wiedergabe wird nur kurz leiser und läuft danach normal weiter.
- `clear_notification` schließt die Meldung vorzeitig; Test lokal und über Home Assistant.

### Einrichtung & Betrieb

- Hintergrunddienst (Bedienungshilfe) ohne sichtbare App, startet nach Neustart automatisch; schaltet sich mit einmalig per adb erteilter Berechtigung nach „Beenden erzwingen“ selbst wieder ein.
- Home Assistant im Netzwerk suchen (mDNS und Netzwerk-Scan).
- Einrichtung per Browser: Token, Panels und Gruppen bequem am Handy eintragen.
- Einstellungen in Reitern (Panels, Türglocke, Verbindung), Statusleiste mit Dienst, Autostart, Home Assistant, Türglocke und Versionsnummer.
- App-Logo, TV-Banner, Farben passend zu home_radio.

[1.0.0]: https://github.com/JayLo1401/home.control/releases/tag/v1.0.0
