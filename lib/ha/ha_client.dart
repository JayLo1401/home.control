import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'ha_entity.dart';

enum HaStatus { notConfigured, connecting, connected, authFailed, disconnected }

/// Lokale Verbindung zu Home Assistant ueber die WebSocket-API
/// (Long-Lived Access Token, Zustaende per `state_changed` live).
class HaClient extends ChangeNotifier {
  String _url = '';
  String _token = '';
  bool _insecure = false;

  WebSocket? _ws;
  StreamSubscription? _sub;
  int _nextId = 1;
  final _pending = <int, Completer<dynamic>>{};
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int _retry = 0;
  int _gen = 0; // verwirft Antworten veralteter Verbindungsversuche
  bool _disposed = false;

  final Map<String, HaEntity> states = {};
  HaStatus status = HaStatus.notConfigured;
  String? error;
  String? haVersion;

  /// Setzt die Zugangsdaten; verbindet nur neu, wenn sich etwas geaendert hat.
  void configure(String url, String token, {bool allowBadCertificates = false}) {
    final normalized = normalizeUrl(url);
    if (normalized == _url && token == _token && allowBadCertificates == _insecure &&
        status != HaStatus.disconnected && status != HaStatus.authFailed) {
      return;
    }
    _url = normalized;
    _token = token.trim();
    _insecure = allowBadCertificates;
    _retry = 0;
    _close();
    if (_url.isEmpty || _token.isEmpty) {
      _setStatus(HaStatus.notConfigured);
    } else {
      _connect();
    }
  }

  /// Bei geschlossener Verbindung sofort neu versuchen (z. B. beim Oeffnen des Panels).
  void ensureConnected() {
    if (status == HaStatus.disconnected) {
      _retry = 0;
      _reconnectTimer?.cancel();
      _connect();
    }
  }

  static String normalizeUrl(String url) {
    var u = url.trim();
    if (u.isEmpty) return '';
    if (!u.contains('://')) u = 'http://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  static String _wsUrl(String httpUrl) {
    final uri = Uri.parse(httpUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return uri.replace(scheme: scheme, path: '${uri.path}/api/websocket').toString();
  }

  Future<void> _connect() async {
    if (_disposed) return;
    final gen = _gen;
    _setStatus(HaStatus.connecting);
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8)
        ..badCertificateCallback = (_, _, _) => _insecure;
      final ws = await WebSocket.connect(_wsUrl(_url), customClient: client)
          .timeout(const Duration(seconds: 10));
      if (_disposed || gen != _gen) {
        ws.close();
        return;
      }
      _ws = ws;
      _sub = ws.listen(_onMessage, onDone: _onClosed, onError: (_) => _onClosed(), cancelOnError: true);
    } catch (e) {
      if (gen != _gen) return;
      error = '$e';
      _onClosed();
    }
  }

  void _onMessage(dynamic raw) {
    final msg = jsonDecode(raw as String) as Map<String, dynamic>;
    switch (msg['type']) {
      case 'auth_required':
        _ws?.add(jsonEncode({'type': 'auth', 'access_token': _token}));
      case 'auth_ok':
        haVersion = msg['ha_version'] as String?;
        _retry = 0;
        error = null;
        _afterAuth();
      case 'auth_invalid':
        error = msg['message'] as String? ?? 'Token ungültig';
        _setStatus(HaStatus.authFailed);
        _close();
      case 'result':
        final c = _pending.remove(msg['id']);
        if (c == null) return;
        if (msg['success'] == true) {
          c.complete(msg['result']);
        } else {
          c.completeError(HaException((msg['error'] as Map?)?['message'] as String? ?? 'Fehler'));
        }
      case 'pong':
        _pending.remove(msg['id'])?.complete(null);
      case 'event':
        final data = (msg['event'] as Map?)?['data'] as Map?;
        if (data == null) return;
        final id = data['entity_id'] as String;
        final ns = data['new_state'];
        if (ns == null) {
          states.remove(id);
        } else {
          states[id] = HaEntity.fromJson((ns as Map).cast<String, dynamic>());
        }
        notifyListeners();
    }
  }

  Future<void> _afterAuth() async {
    try {
      await _send({'type': 'subscribe_events', 'event_type': 'state_changed'});
      final list = await _send({'type': 'get_states'}) as List;
      states
        ..clear()
        ..addEntries(list.map((j) {
          final e = HaEntity.fromJson((j as Map).cast<String, dynamic>());
          return MapEntry(e.entityId, e);
        }));
      _setStatus(HaStatus.connected);
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) => _ping());
    } catch (e) {
      error = '$e';
      _close();
      _onClosed();
    }
  }

  Future<void> _ping() async {
    try {
      await _send({'type': 'ping'}).timeout(const Duration(seconds: 10));
    } catch (_) {
      _close();
      _onClosed();
    }
  }

  Future<dynamic> _send(Map<String, dynamic> msg) {
    final ws = _ws;
    if (ws == null) return Future.error(HaException('Nicht verbunden'));
    final id = _nextId++;
    final c = Completer<dynamic>();
    _pending[id] = c;
    ws.add(jsonEncode({...msg, 'id': id}));
    return c.future;
  }

  Future<void> callService(String domain, String service, {String? entityId, Map<String, dynamic>? data}) {
    return _send({
      'type': 'call_service',
      'domain': domain,
      'service': service,
      'service_data': ?data,
      if (entityId != null) 'target': {'entity_id': entityId},
    }).timeout(const Duration(seconds: 10));
  }

  void _onClosed() {
    _pingTimer?.cancel();
    _sub?.cancel();
    _sub = null;
    _ws = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(HaException('Verbindung getrennt'));
    }
    _pending.clear();
    if (_disposed || status == HaStatus.authFailed || _url.isEmpty) return;
    _setStatus(HaStatus.disconnected);
    _reconnectTimer?.cancel();
    final delay = Duration(seconds: min(30, 2 << min(_retry, 4)));
    _retry++;
    _reconnectTimer = Timer(delay, _connect);
  }

  void _close() {
    _gen++;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _sub?.cancel();
    _sub = null;
    _ws?.close();
    _ws = null;
  }

  void _setStatus(HaStatus s) {
    status = s;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _close();
    super.dispose();
  }
}

class HaException implements Exception {
  final String message;
  HaException(this.message);
  @override
  String toString() => message;
}
