import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../ha/ha_client.dart';
import '../ha/mobile_app.dart';
import 'doorbell_popup.dart';
import 'hold_popup.dart';
import 'quick_panel.dart';

enum _Mode { none, panel, hold, doorbell }

/// Laeuft in der vorgewaermten Engine des Hintergrunddienstes.
/// Haelt die HA-Verbindung dauerhaft offen: Panel zeigt sofort aktuelle Werte,
/// Tuerglocken-Nachrichten aus HA kommen jederzeit an.
class OverlayApp extends StatefulWidget {
  const OverlayApp({super.key});

  @override
  State<OverlayApp> createState() => _OverlayAppState();
}

class _OverlayAppState extends State<OverlayApp> {
  static const _channel = MethodChannel('home_control/overlay');

  final _ha = HaClient();
  final _panelKey = GlobalKey<QuickPanelState>();
  final _holdKey = GlobalKey<HoldPopupState>();
  StreamSubscription? _pushSub;
  AppConfig _config = AppConfig();
  _Mode _mode = _Mode.none;
  PanelConfig? _panel;
  bool _holdReleased = false;
  DoorbellMessage? _doorbell;
  int _doorbellSeq = 0;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_onCall);
    _pushSub = _ha.notifications.listen((ev) => _ring(DoorbellMessage.fromPush(ev)));
    _reloadConfig();
  }

  Future<AppConfig> _reloadConfig() async {
    final c = await AppConfig.load();
    _ha.configure(c.haUrl, c.token, allowBadCertificates: c.allowBadCertificates);
    _ha.setPushWebhook(c.doorbell.webhookId);
    _config = c;
    return c;
  }

  /// Tuerglocke: Gong (mit Ducking) und Meldung ueber allem.
  Future<void> _ring(DoorbellMessage m) async {
    if (m.clear) {
      if (_mode == _Mode.doorbell) _close();
      return;
    }
    final d = _config.doorbell;
    if (m.chime ?? d.chime) {
      _channel.invokeMethod('playChime', {'times': d.chimeRepeat, 'volume': d.volumePercent / 100});
    }
    _doorbell = m;
    _doorbellSeq++;
    await _channel.invokeMethod('open', {'mode': 'doorbell'});
  }

  Future<dynamic> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'show':
        final args = (call.arguments as Map).cast<String, dynamic>();
        if (args['mode'] == 'doorbell') {
          setState(() => _mode = _Mode.doorbell);
          return null;
        }
        _holdReleased = false;
        _ha.ensureConnected();
        final c = await _reloadConfig();
        final key = args['key'] as int?;
        final index = args['panelIndex'] as int?;
        final panel = key != null
            ? c.panelForKey(key)
            : (index != null && index < c.panels.length ? c.panels[index] : null);
        final mode = args['mode'] == 'hold' && panel?.longPress != null ? _Mode.hold : _Mode.panel;
        setState(() {
          _panel = panel;
          _mode = mode;
        });
      case 'holdRelease':
        // Kann eintreffen, bevor das Popup gebaut ist (Konfiguration wird noch geladen).
        _holdReleased = true;
        _holdKey.currentState?.release();
      case 'back':
        return _mode == _Mode.panel && (_panelKey.currentState?.handleBack() ?? false);
      case 'hidden':
        if (_mode == _Mode.doorbell) _channel.invokeMethod('stopChime');
        setState(() => _mode = _Mode.none);
      case 'key':
        final key = PanelKey.values.asNameMap()[call.arguments as String];
        if (key == null) return null;
        if (_mode == _Mode.panel) _panelKey.currentState?.handleKey(key);
        if (_mode == _Mode.doorbell && key == PanelKey.select) _close();
      case 'reload':
        await _reloadConfig();
      case 'testDoorbell':
        await _ring(DoorbellMessage(title: 'Türglocke', message: 'Test: Es hat an der Tür geläutet'));
    }
    return null;
  }

  void _close() => _channel.invokeMethod('close');

  @override
  void dispose() {
    _pushSub?.cancel();
    _ha.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTvTheme().copyWith(scaffoldBackgroundColor: Colors.transparent),
      color: Colors.transparent,
      home: Material(
        type: MaterialType.transparency,
        // Beim Schliessen wird alles entfernt -> jede Oeffnung startet mit frischem Zustand.
        child: switch (_mode) {
          _Mode.none => const SizedBox.shrink(),
          _Mode.panel => QuickPanel(key: _panelKey, ha: _ha, config: _config, panel: _panel, onClose: _close),
          _Mode.hold => HoldPopup(
              key: _holdKey,
              ha: _ha,
              config: _config,
              action: _panel!.longPress!,
              releasedBeforeStart: _holdReleased,
              onClose: _close,
            ),
          _Mode.doorbell => DoorbellPopup(
              key: ValueKey(_doorbellSeq), // erneutes Laeuten startet die Anzeige neu
              message: _doorbell!,
              config: _config,
              onClose: _close,
            ),
        },
      ),
    );
  }
}
