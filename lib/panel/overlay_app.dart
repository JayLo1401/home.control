import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../ha/ha_client.dart';
import 'hold_popup.dart';
import 'quick_panel.dart';

enum _Mode { none, panel, hold }

/// Laeuft in der vorgewaermten Engine des Hintergrunddienstes.
/// Haelt die HA-Verbindung dauerhaft offen, damit das Panel sofort aktuelle Werte zeigt.
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
  AppConfig _config = AppConfig();
  _Mode _mode = _Mode.none;
  PanelConfig? _panel;
  bool _holdReleased = false;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_onCall);
    _reloadConfig();
  }

  Future<AppConfig> _reloadConfig() async {
    final c = await AppConfig.load();
    _ha.configure(c.haUrl, c.token, allowBadCertificates: c.allowBadCertificates);
    _config = c;
    return c;
  }

  Future<dynamic> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'show':
        final args = (call.arguments as Map).cast<String, dynamic>();
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
        setState(() => _mode = _Mode.none);
      case 'key':
        final key = PanelKey.values.asNameMap()[call.arguments as String];
        if (key != null && _mode == _Mode.panel) _panelKey.currentState?.handleKey(key);
    }
    return null;
  }

  void _close() => _channel.invokeMethod('close');

  @override
  void dispose() {
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
        },
      ),
    );
  }
}
