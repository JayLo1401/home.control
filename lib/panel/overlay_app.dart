import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../ha/ha_client.dart';
import 'quick_panel.dart';

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
  AppConfig _config = AppConfig();
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_onCall);
    _reloadConfig();
  }

  Future<void> _reloadConfig() async {
    final c = await AppConfig.load();
    _ha.configure(c.haUrl, c.token, allowBadCertificates: c.allowBadCertificates);
    if (mounted) setState(() => _config = c);
  }

  Future<dynamic> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'shown':
        setState(() => _visible = true);
        _ha.ensureConnected();
        await _reloadConfig();
      case 'hidden':
        setState(() => _visible = false);
      case 'key':
        final key = PanelKey.values.asNameMap()[call.arguments as String];
        if (key != null) _panelKey.currentState?.handleKey(key);
    }
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
        // Beim Schliessen wird das Panel entfernt -> jede Oeffnung startet mit frischem
        // Zustand (Auswahl oben links, Auto-Schliessen neu).
        child: _visible
            ? QuickPanel(key: _panelKey, ha: _ha, config: _config, onClose: _close)
            : const SizedBox.shrink(),
      ),
    );
  }
}
