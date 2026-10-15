import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/native_bridge.dart';

class HaInstance {
  final String name;
  final String url;
  final String? version;
  const HaInstance(this.name, this.url, this.version);
}

/// Sucht Home Assistant im lokalen Netz: per mDNS und parallel per Scan
/// des eigenen /24-Netzes auf Port 8123 (falls mDNS im WLAN blockiert ist).
class HaDiscovery {
  static const _defaultPort = 8123;

  static Future<List<HaInstance>> search() async {
    final results = await Future.wait([_mdns(), _scanSubnets()]);
    final byUrl = <String, HaInstance>{};
    for (final list in results) {
      for (final i in list) {
        byUrl.putIfAbsent(i.url, () => i); // mDNS zuerst -> hat Namen und Version
      }
    }
    return byUrl.values.toList();
  }

  static Future<List<HaInstance>> _mdns() async {
    try {
      final found = await NativeBridge.discoverHomeAssistant();
      return [
        for (final m in found)
          if (m['host'] != null && !(m['host'] as String).contains(':')) // nur IPv4
            HaInstance(
              m['name'] as String? ?? 'Home Assistant',
              // IP statt *.local-Name: wird von Android nicht immer aufgeloest
              'http://${m['host']}:${m['port'] ?? _defaultPort}',
              m['version'] as String?,
            ),
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<List<HaInstance>> _scanSubnets() async {
    final prefixes = <String>{};
    for (final iface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final a in iface.addresses) {
        final parts = a.address.split('.');
        if (a.isLoopback || parts.length != 4) continue;
        if (_isPrivate(parts)) prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
      }
    }
    final hosts = [
      for (final p in prefixes)
        for (var i = 1; i < 255; i++) '$p.$i',
    ];
    final checks = await Future.wait(hosts.map(_probe));
    return checks.whereType<HaInstance>().toList();
  }

  static bool _isPrivate(List<String> p) {
    final a = int.tryParse(p[0]) ?? 0, b = int.tryParse(p[1]) ?? 0;
    return a == 10 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31);
  }

  /// Port offen und /manifest.json gehoert zu Home Assistant?
  static Future<HaInstance?> _probe(String host) async {
    try {
      final s = await Socket.connect(host, _defaultPort, timeout: const Duration(milliseconds: 700));
      s.destroy();
    } catch (_) {
      return null;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await client.getUrl(Uri.parse('http://$host:$_defaultPort/manifest.json'));
      final res = await req.close().timeout(const Duration(seconds: 3));
      final body = await utf8.decodeStream(res).timeout(const Duration(seconds: 3));
      if (!body.contains('Home Assistant')) return null;
      return HaInstance('Home Assistant', 'http://$host:$_defaultPort', null);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
