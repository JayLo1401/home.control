import 'package:flutter/services.dart';

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

  static Future<void> openAccessibilitySettings() => _ch.invokeMethod('openAccessibilitySettings');

  static Future<TriggerKey> getTriggerKey() async =>
      TriggerKey.fromMap(await _ch.invokeMethod<Map>('getTriggerKey') ?? {});

  static Future<void> setTriggerKey(int code) => _ch.invokeMethod('setTriggerKey', {'code': code});

  /// Wartet, bis der Dienst die naechste Taste meldet.
  static Future<TriggerKey> learnKey() async =>
      TriggerKey.fromMap(await _ch.invokeMethod<Map>('learnKey') ?? {});

  static Future<void> cancelLearn() => _ch.invokeMethod('cancelLearn');

  static Future<bool> showOverlay() async => await _ch.invokeMethod<bool>('showOverlay') ?? false;
}
