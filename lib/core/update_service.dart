import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Neuere Version auf dem Update-Server.
class AvailableUpdate {
  final String version;
  final int? versionCode;
  final String url;
  final String? sha256;

  const AvailableUpdate({required this.version, this.versionCode, required this.url, this.sha256});
}

/// Updates aus dem oeffentlichen Nexus-Raw-Repository, in das die CI
/// veroeffentlicht (.github/workflows/release.yml):
///
/// ```
/// <base>/android/release/latest/version.json
/// {"version": "1.0.3", "versionCode": 117, "url": ".../home_control-1.0.3.apk", "sha256": "..."}
/// ```
///
/// Die Basis-URL baut nur die CI ein (`--dart-define=UPDATE_BASE_URL=...`);
/// lokal gebaute Versionen aktualisieren sich nie selbst.
class UpdateService {
  static const baseUrl = String.fromEnvironment('UPDATE_BASE_URL');
  static const _ch = MethodChannel('home_control/update');
  static const _autoKey = 'auto_update';

  static bool get supported => baseUrl != '';

  /// Automatisch aktualisieren (Standard: ja). Liest frisch von der Platte,
  /// weil die Einstellungs-App und der Dienst je eine eigene Engine haben.
  static Future<bool> autoUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getBool(_autoKey) ?? true;
  }

  static Future<void> setAutoUpdate(bool on) async =>
      (await SharedPreferences.getInstance()).setBool(_autoKey, on);

  /// Installierte Version (versionName, versionCode).
  static Future<(String, int)> currentVersion() async {
    final m = await _ch.invokeMapMethod<String, dynamic>('appVersion') ?? const {};
    return ('${m['name'] ?? ''}', (m['code'] as num?)?.toInt() ?? 0);
  }

  /// Darf die App Pakete installieren ("Unbekannte Apps installieren")?
  static Future<bool> canInstall() async => await _ch.invokeMethod<bool>('canInstall') ?? false;

  /// Oeffnet die Systemseite dafuer; `false`, wenn das Geraet keine hat.
  static Future<bool> openInstallPermission() async =>
      await _ch.invokeMethod<bool>('openInstallPermission') ?? false;

  /// Neuere Version oder null (keine, offline, kein Server).
  static Future<AvailableUpdate?> check() async {
    if (!supported) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse('$baseUrl/android/release/latest/version.json'));
      req.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final update = AvailableUpdate(
        version: json['version'] as String,
        versionCode: (json['versionCode'] as num?)?.toInt(),
        url: json['url'] as String,
        sha256: json['sha256'] as String?,
      );
      final (name, code) = await currentVersion();
      return isNewer(update, name, code) ? update : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Laedt [update] herunter, prueft die Pruefsumme und uebergibt die APK dem
  /// System. Wirft [UpdateException] bei Fehlern.
  static Future<void> install(AvailableUpdate update, {void Function(double progress)? onProgress}) async {
    if (!await canInstall()) {
      throw const UpdateException('Die App darf keine Updates installieren („Unbekannte Apps installieren“).');
    }
    final dir = await _ch.invokeMethod<String>('cacheDir');
    final file = File('$dir/home_control_update.apk');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final res = await (await client.getUrl(Uri.parse(update.url))).close();
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw UpdateException('Download fehlgeschlagen (HTTP ${res.statusCode}).');
      }
      final total = res.contentLength;
      final sink = file.openWrite();
      final digest = _DigestSink();
      final hasher = sha256.startChunkedConversion(digest);
      var received = 0;
      try {
        await for (final chunk in res) {
          sink.add(chunk);
          hasher.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call(received / total);
        }
      } finally {
        await sink.close();
        hasher.close();
      }
      final expected = update.sha256?.toLowerCase();
      if (expected != null && digest.value.toString() != expected) {
        await file.delete();
        throw const UpdateException('Die heruntergeladene Datei ist beschädigt.');
      }
    } on SocketException catch (e) {
      throw UpdateException('Download fehlgeschlagen (${e.message}).');
    } finally {
      client.close(force: true);
    }
    try {
      await _ch.invokeMethod('install', {'path': file.path});
    } on PlatformException catch (e) {
      throw UpdateException('Installation fehlgeschlagen (${e.message}).');
    }
  }
}

/// Ist [u] neuer als die installierte Version? Primaer der versionCode (die
/// CI zaehlt ihn hoch), sonst die Versionsnummer.
bool isNewer(AvailableUpdate u, String currentName, int currentCode) {
  final byName = compareVersions(u.version, currentName);
  if (u.versionCode != null && currentCode > 0) return u.versionCode! > currentCode && byName >= 0;
  return byName > 0;
}

/// Vergleicht Versionen numerisch ("1.10.0" > "1.9.2").
int compareVersions(String a, String b) {
  List<int> parts(String v) => v.split('+').first.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0, y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

class UpdateException implements Exception {
  final String message;
  const UpdateException(this.message);

  @override
  String toString() => message;
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
