import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'ha/ha_client.dart';
import 'panel/overlay_app.dart';
import 'settings/settings_page.dart';

/// Einstiegspunkt der Einstellungs-App.
void main() {
  runApp(HomeControlApp(ha: HaClient()));
}

/// Einstiegspunkt der Overlay-Engine, die der Hintergrunddienst startet
/// (`PanelAccessibilityService`).
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OverlayApp());
}

class HomeControlApp extends StatelessWidget {
  final HaClient ha;
  const HomeControlApp({super.key, required this.ha});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Home Control',
      debugShowCheckedModeBanner: false,
      theme: buildTvTheme(),
      home: SettingsPage(ha: ha),
    );
  }
}
