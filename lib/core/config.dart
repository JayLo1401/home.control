import 'package:shared_preferences/shared_preferences.dart';

/// App-Konfiguration. Wird von App und Overlay-Engine gemeinsam genutzt
/// (beide laufen im selben Prozess, deshalb vor jedem Lesen `reload()`).
class AppConfig {
  String haUrl;
  String token;
  bool allowBadCertificates;
  List<String> entities;
  int columns;
  int panelPercent;
  int autoCloseSeconds;

  AppConfig({
    this.haUrl = '',
    this.token = '',
    this.allowBadCertificates = false,
    List<String>? entities,
    this.columns = 4,
    this.panelPercent = 80,
    this.autoCloseSeconds = 30,
  }) : entities = entities ?? [];

  bool get isConfigured => haUrl.isNotEmpty && token.isNotEmpty;

  static Future<AppConfig> load() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    return AppConfig(
      haUrl: p.getString('ha_url') ?? '',
      token: p.getString('ha_token') ?? '',
      allowBadCertificates: p.getBool('ha_insecure') ?? false,
      entities: p.getStringList('entities') ?? [],
      columns: p.getInt('columns') ?? 4,
      panelPercent: p.getInt('panel_percent') ?? 80,
      autoCloseSeconds: p.getInt('auto_close') ?? 30,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('ha_url', haUrl);
    await p.setString('ha_token', token);
    await p.setBool('ha_insecure', allowBadCertificates);
    await p.setStringList('entities', entities);
    await p.setInt('columns', columns);
    await p.setInt('panel_percent', panelPercent);
    await p.setInt('auto_close', autoCloseSeconds);
  }
}
