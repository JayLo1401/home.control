import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'ha_client.dart';

/// Registrierung als Geraet der HA-Integration `mobile_app` (wie die Companion-App).
/// HA legt dabei den Dienst `notify.mobile_app_<geraetename>` an; Nachrichten kommen
/// lokal ueber den WebSocket-Push-Kanal (keine Cloud noetig).
class MobileAppRegistration {
  final String webhookId;
  final String? notifyService;
  MobileAppRegistration(this.webhookId, this.notifyService);
}

String newDeviceId() {
  final r = Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// Name -> Objekt-ID wie HA (vereinfachtes slugify): "Home Control MiTV" -> "home_control_mitv".
String haSlug(String s) {
  const map = {'ä': 'a', 'ö': 'o', 'ü': 'u', 'ß': 'ss', 'Ä': 'a', 'Ö': 'o', 'Ü': 'u'};
  final t = s.split('').map((c) => map[c] ?? c).join().toLowerCase();
  return t.replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
}

Future<MobileAppRegistration> registerMobileApp({
  required HaClient ha,
  required String url,
  required String token,
  required String deviceId,
  required String deviceName,
  required Map<String, String> device,
  bool allowBadCertificates = false,
}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..badCertificateCallback = (_, _, _) => allowBadCertificates;
  try {
    final req = await client.postUrl(Uri.parse('$url/api/mobile_app/registrations'));
    req.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
      ..contentType = ContentType.json;
    req.write(jsonEncode({
      'device_id': deviceId,
      'app_id': 'org.lotzapp.home_control',
      'app_name': 'Home Control',
      'app_version': device['appVersion'] ?? '0',
      'device_name': deviceName,
      'manufacturer': device['manufacturer'] ?? 'Android',
      'model': device['model'] ?? 'TV',
      'os_name': 'Android',
      'os_version': device['osVersion'] ?? '',
      'supports_encryption': false,
      // Nachrichten lokal ueber den WebSocket-Kanal statt ueber einen Push-Dienst
      'app_data': {'push_websocket_channel': true},
    }));
    final res = await req.close().timeout(const Duration(seconds: 10));
    final body = await utf8.decodeStream(res);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw HaException('Registrierung fehlgeschlagen (${res.statusCode}): $body');
    }
    final webhook = (jsonDecode(body) as Map)['webhook_id'] as String;
    return MobileAppRegistration(webhook, await findNotifyService(ha, deviceName));
  } finally {
    client.close(force: true);
  }
}

/// Sucht den notify-Dienst des Geraets (HA braucht nach der Registrierung einen Moment).
Future<String?> findNotifyService(HaClient ha, String deviceName) async {
  final expected = 'mobile_app_${haSlug(deviceName)}';
  for (var i = 0; i < 6; i++) {
    try {
      final notify = (await ha.getServices())['notify'] as Map?;
      if (notify != null) {
        if (notify.containsKey(expected)) return expected;
        // HA haengt bei Namensgleichheit "_2" usw. an
        final similar = notify.keys.cast<String>().where((k) => k.startsWith(expected)).toList()..sort();
        if (similar.isNotEmpty) return similar.last;
      }
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }
  return null;
}

/// Inhalt einer Tuerglocken-Nachricht aus HA.
class DoorbellMessage {
  final String title;
  final String message;
  final int? duration;
  final bool? chime;
  final String? camera;
  final bool clear;

  DoorbellMessage({
    required this.title,
    required this.message,
    this.duration,
    this.chime,
    this.camera,
    this.clear = false,
  });

  /// Aus dem Push-Event: {message, title, data: {duration, chime, camera}}.
  factory DoorbellMessage.fromPush(Map<String, dynamic> ev) {
    final data = (ev['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final message = '${ev['message'] ?? ''}';
    return DoorbellMessage(
      title: '${ev['title'] ?? 'Türglocke'}',
      message: message,
      duration: (data['duration'] as num?)?.toInt(),
      chime: switch (data['chime']) {
        bool b => b,
        'none' || 'off' || 'false' => false,
        _ => null,
      },
      camera: data['camera'] as String?,
      // wie bei der Companion-App: Nachricht wieder schliessen
      clear: message == 'clear_notification',
    );
  }
}
