# Home Control

Home-Assistant-Schnellpanel für Android TV (Ersatz für QuickBars), passend zu home_radio gestaltet.

Eine angelernte Fernbedienungstaste blendet über jedem laufenden Bild ein Panel ein (Standard: 80 % des Bildschirms).
Mit den Pfeiltasten wählst du, mit OK schaltest du, mit Zurück oder der Panel-Taste schließt du es.

## Funktionsweise

- **`PanelAccessibilityService`** (Kotlin) ist ein Bedienungshilfen-Dienst mit Key-Filter. Er fängt die angelernte Taste ab und
  zeigt eine vorgewärmte Flutter-Engine (`overlayMain`) als `TYPE_ACCESSIBILITY_OVERLAY` an. Dafür braucht die App keine
  Berechtigung „Über anderen Apps anzeigen“, und das laufende Video wird nicht pausiert.
  Solange das Panel offen ist, leitet der Dienst die Pfeiltasten und OK an Flutter weiter. Das Overlay braucht dafür keinen Fokus.
- **`HaClient`** spricht die WebSocket-API von Home Assistant (Long-Lived Token, Live-Updates über `state_changed`) und verbindet sich bei Abbruch automatisch neu.
- **Einstellungs-App**: Dienststatus, Taste anlernen, URL und Token, Auswahl und Reihenfolge der Entitäten, Spalten, Panelgröße und Auto-Schließen.
  Unter „Einrichtung per Browser“ lassen sich Token und Entitäten vom Handy aus eintragen (`http://<tv-ip>:8765`).

## Einrichtung

1. Installiere die APK: `adb install -r build/app/outputs/flutter-apk/app-release.apk`
2. Aktiviere den Dienst unter Einstellungen → Geräteeinstellungen → Bedienungshilfen → **Home Control Panel**.
   Falls der Eintrag fehlt oder sich nicht einschalten lässt, geht es per ADB:
   ```
   adb shell settings put secure enabled_accessibility_services org.lotzapp.home_control/.PanelAccessibilityService
   adb shell settings put secure accessibility_enabled 1
   ```
3. Öffne die App, wähle **Taste anlernen** und drücke z. B. die Menütaste.
4. Trage URL und Token ein (oder nutze die Browser-Einrichtung) und wähle die Entitäten aus.

## Bauen & Installieren

```
./scripts/deploy.ps1                                   # Debug bauen, Geräte auswählen, installieren
./scripts/deploy.ps1 -Release -EnableService -Launch   # Release + Dienst per adb einschalten + App starten
./scripts/deploy.ps1 -Release -SkipBuild -All          # letzte APK auf alle Geräte
```

```
flutter build apk --release --no-tree-shake-icons --split-per-abi   # kleinere APKs
flutter test
```

`--no-tree-shake-icons` ist nötig, weil die Symbole aus HA (`mdi:…`) erst zur Laufzeit feststehen.
Die Symbole stammen aus [Material Design Icons](https://pictogrammers.com/library/mdi/) (@mdi/font 7.4.47, Apache 2.0)
und liegen unter `assets/mdi/`.

Hinweis: In `android/gradle.properties` steht `kotlin.incremental=false`. Das ist nötig, weil das Projekt auf D: und der Pub-Cache auf C: liegen.
