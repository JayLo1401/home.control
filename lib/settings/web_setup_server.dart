import 'dart:convert';
import 'dart:io';

import '../core/config.dart';

/// Kleiner Webserver im LAN: URL, Token und Entitaeten bequem vom Handy/PC
/// eintragen statt mit der Fernbedienung zu tippen.
class WebSetupServer {
  static const port = 8765;

  HttpServer? _server;
  final void Function() onSaved;

  WebSetupServer({required this.onSaved});

  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_handle);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  static Future<List<String>> localAddresses() async {
    final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
    return [
      for (final i in ifs)
        for (final a in i.addresses)
          if (!a.isLoopback) 'http://${a.address}:$port',
    ];
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      if (req.method == 'POST' && req.uri.path == '/save') {
        final body = await utf8.decodeStream(req);
        final form = Uri.splitQueryString(body);
        final c = await AppConfig.load();
        c.haUrl = (form['url'] ?? c.haUrl).trim();
        final token = (form['token'] ?? '').trim();
        if (token.isNotEmpty) c.token = token;
        c.allowBadCertificates = form['insecure'] == 'on';
        if (form.containsKey('panels')) c.panelsFromText(form['panels']!);
        await c.save();
        onSaved();
        _html(req, _page(c, saved: true));
        return;
      }
      _html(req, _page(await AppConfig.load()));
    } catch (e) {
      req.response
        ..statusCode = 500
        ..write('Fehler: $e');
      await req.response.close();
    }
  }

  void _html(HttpRequest req, String html) {
    req.response.headers.contentType = ContentType.html;
    req.response.write(html);
    req.response.close();
  }

  static String _esc(String s) => const HtmlEscape().convert(s);

  String _page(AppConfig c, {bool saved = false}) => '''
<!doctype html>
<html lang="de"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Home Control Einrichtung</title>
<style>
  body{font-family:system-ui,sans-serif;background:#000;color:#eee;margin:0;padding:16px}
  main{max-width:640px;margin:auto;background:#141A22;border:2px solid #2F9E5C;border-radius:20px;padding:20px}
  h1{color:#2F9E5C;margin-top:0;font-size:1.5em}
  label{display:block;margin:16px 0 6px;color:#aaa}
  input[type=text],input[type=password],textarea{width:100%;box-sizing:border-box;padding:10px;border-radius:10px;border:1px solid #333;background:#1E2630;color:#eee;font-size:1em}
  textarea{height:360px;font-family:monospace}
  code{color:#FFB300}
  button{margin-top:20px;width:100%;padding:14px;border:0;border-radius:12px;background:#2F9E5C;color:#fff;font-size:1.1em}
  .ok{background:#1B6B3E;padding:10px;border-radius:10px}
  small{color:#888}
</style></head><body><main>
<h1>🏠 Home Control</h1>
${saved ? '<p class="ok">Gespeichert ✔ – die TV-App übernimmt die Werte sofort.</p>' : ''}
<form method="post" action="/save">
  <label>Home Assistant URL</label>
  <input type="text" name="url" value="${_esc(c.haUrl)}" placeholder="http://192.168.1.10:8123">
  <label>Long-Lived Access Token ${c.token.isNotEmpty ? '<small>(gesetzt – leer lassen = unverändert)</small>' : ''}</label>
  <input type="password" name="token" placeholder="${c.token.isNotEmpty ? '••••••••' : 'Profil → Sicherheit → Token erstellen'}">
  <label><input type="checkbox" name="insecure" ${c.allowBadCertificates ? 'checked' : ''}> Selbstsignierte Zertifikate erlauben</label>
  <label>Panels, Gruppen &amp; Entitäten</label>
  <textarea name="panels" placeholder="== Wohnzimmer&#10;light.wohnzimmer&#10;-- Whirlpool&#10;switch.whirlpool_pumpe&#10;sensor.whirlpool_temperatur&#10;--&#10;scene.kino">${_esc(c.panelsToText())}</textarea>
  <small>
    <code>== Name</code> beginnt ein Panel, <code>-- Name</code> eine Gruppe, <code>--</code> allein beendet die Gruppe.
    Eine Entität pro Zeile, Reihenfolge = Anzeige.
    Werte in der Gruppenüberschrift: <code>temperatur: sensor.x</code>, <code>feuchte: sensor.y</code>, <code>leistung: sensor.z</code>.
    Eigener Name/Symbol: <code>switch.pumpe | Pumpe | mdi:pump</code> (Symbolnamen wie in HA, siehe pictogrammers.com/library/mdi).
    Taste und Lang-Drücken-Aktion werden in der TV-App eingestellt und bleiben erhalten, solange der Panelname gleich bleibt.
  </small>
  <button type="submit">Speichern</button>
</form>
</main></body></html>
''';
}
