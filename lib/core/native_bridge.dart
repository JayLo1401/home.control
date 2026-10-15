import 'package:flutter/services.dart';

import 'config.dart';

class TriggerKey {
  final int code;
  final String name;
  const TriggerKey(this.code, this.name);

  bool get isSet => code != 0;

  factory TriggerKey.fromMap(Map<dynamic, dynamic> m) =>
      TriggerKey(m['code'] as int? ?? 0, m['name'] as String? ?? '');
}

/// Kanal zur Android-Seite (Hintergrunddienst, Tasten).
class NativeBridge {
  static const _ch = MethodChannel('home_control/native');

  static Future<bool> isServiceEnabled() async =>
      await _ch.invokeMethod<bool>('isServiceEnabled') ?? false;

  /// Hat die App per adb WRITE_SECURE_SETTINGS (Dienst kann sich selbst wieder einschalten)?
  static Future<bool> canAutoEnable() async => await _ch.invokeMethod<bool>('canAutoEnable') ?? false;

  static Future<void> openAccessibilitySettings() => _ch.invokeMethod('openAccessibilitySettings');

  /// Taste aus Version 0.1 (vor den Panels) – nur fuer die Migration.
  static Future<TriggerKey> getLegacyTriggerKey() async =>
      TriggerKey.fromMap(await _ch.invokeMethod<Map>('getLegacyTriggerKey') ?? {});

  /// Teilt dem Dienst mit, welche Tasten Panels oeffnen und welche eine Lang-Druecken-Aktion haben.
  static Future<void> syncKeyBindings(AppConfig c) => _ch.invokeMethod('setKeyBindings', {
        'bindings': [
          for (final p in c.panels)
            if (p.keyCode != 0) {'code': p.keyCode, 'longPress': p.longPress != null},
        ],
      });

  /// Wartet, bis der Dienst die naechste Taste meldet.
  static Future<TriggerKey> learnKey() async =>
      TriggerKey.fromMap(await _ch.invokeMethod<Map>('learnKey') ?? {});

  static Future<void> cancelLearn() => _ch.invokeMethod('cancelLearn');

  static Future<bool> showOverlay({int panelIndex = 0}) async =>
      await _ch.invokeMethod<bool>('showOverlay', {'panelIndex': panelIndex}) ?? false;

  /// Overlay-Engine im Dienst laedt die Konfiguration neu.
  static Future<void> reloadOverlayConfig() => _ch.invokeMethod('reloadOverlayConfig');

  /// Tuerglocke lokal testen (ohne Home Assistant).
  static Future<bool> testDoorbell() async => await _ch.invokeMethod<bool>('testDoorbell') ?? false;

  static Future<Map<String, String>> deviceInfo() async =>
      (await _ch.invokeMethod<Map>('deviceInfo') ?? {}).map((k, v) => MapEntry('$k', '${v ?? ''}'));

  /// mDNS-Suche nach `_home-assistant._tcp` (Android NsdManager).
  static Future<List<Map<dynamic, dynamic>>> discoverHomeAssistant({int timeoutMs = 4000}) async {
    final list = await _ch.invokeMethod<List>('discoverHomeAssistant', {'timeoutMs': timeoutMs});
    return [...?list?.cast<Map<dynamic, dynamic>>()];
  }
}
