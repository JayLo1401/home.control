import 'package:flutter/services.dart';

import 'config.dart';
import 'native_bridge.dart';

/// Sicherungsdatei in Download/HomeControl (siehe BackupPlugin.kt).
class BackupFile {
  /// Dateipfad oder content://-URI – nur fuer BackupPlugin von Bedeutung.
  final String id;
  final String name;
  final DateTime modified;

  const BackupFile({required this.id, required this.name, required this.modified});
}

/// Sichert die komplette Konfiguration als JSON in den oeffentlichen Ordner
/// Download/HomeControl, der eine Deinstallation der App uebersteht.
class Backup {
  static const _ch = MethodChannel('home_control/backup');

  /// Liefert den Speicherort, z. B. "Download/HomeControl/...".
  static Future<String> create(AppConfig c) async {
    final model = (await NativeBridge.deviceInfo())['model'] ?? '';
    final device = model.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    final name = ['home_control', if (device.isNotEmpty) device, _timestamp(DateTime.now())].join('_');
    return (await _ch.invokeMethod<String>('save', {'name': '$name.json', 'content': c.toBackupJson()}))!;
  }

  static Future<List<BackupFile>> list() async {
    final raw = await _ch.invokeListMethod<Map<Object?, Object?>>('list') ?? const [];
    return [
      for (final m in raw)
        BackupFile(
          id: m['id']! as String,
          name: m['name']! as String,
          modified: DateTime.fromMillisecondsSinceEpoch((m['modified']! as num).toInt()),
        ),
    ];
  }

  /// Wirft [FormatException], wenn die Datei keine gueltige Sicherung ist.
  static Future<AppConfig> read(BackupFile file) async =>
      AppConfig.fromBackupJson((await _ch.invokeMethod<String>('read', {'id': file.id}))!);

  /// Datei ueber die Dateiauswahl des Systems (auch USB-Stick); null = abgebrochen.
  /// Ohne Dateiauswahl (haeufig auf Android TV): [PlatformException] mit Code NO_PICKER.
  static Future<AppConfig?> pick() async {
    final content = await _ch.invokeMethod<String>('pick');
    return content == null ? null : AppConfig.fromBackupJson(content);
  }

  /// Braucht das Lesen von Sicherungen einer frueheren Installation erst
  /// "Zugriff auf alle Dateien" (Android 11+, noch nicht erlaubt)?
  static Future<bool> canRequestAllFilesAccess() async =>
      await _ch.invokeMethod<bool>('canRequestAllFilesAccess') ?? false;

  /// Oeffnet die Systemeinstellung "Zugriff auf alle Dateien"; false, wenn es sie nicht gibt.
  static Future<bool> requestAllFilesAccess() async =>
      await _ch.invokeMethod<bool>('requestAllFilesAccess') ?? false;

  static String _timestamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }
}
