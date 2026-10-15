import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/native_bridge.dart';
import '../core/theme.dart';
import '../ha/ha_client.dart';
import '../ha/ha_discovery.dart';
import 'panel_edit_page.dart';
import 'web_setup_server.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  final HaClient ha;
  const SettingsPage({super.key, required this.ha});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  AppConfig _config = AppConfig();
  bool _serviceOn = false;
  bool _autoEnable = false;
  final _urlCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  late final WebSetupServer _web = WebSetupServer(onSaved: () => _load(reconnect: true));
  List<String> _webAddresses = [];
  late final AppLifecycleListener _lifecycle;

  HaClient get _ha => widget.ha;

  @override
  void initState() {
    super.initState();
    _ha.addListener(_rebuild);
    _lifecycle = AppLifecycleListener(onResume: _refreshService);
    _load(reconnect: true);
    _refreshService();
  }

  @override
  void dispose() {
    _ha.removeListener(_rebuild);
    _lifecycle.dispose();
    _web.stop();
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _load({bool reconnect = false}) async {
    final c = await AppConfig.load();
    // Migration aus 0.1: bisherige Taste dem ersten Panel zuordnen.
    if (c.panels.isNotEmpty && c.panels.every((p) => p.keyCode == 0)) {
      final legacy = await NativeBridge.getLegacyTriggerKey();
      if (legacy.isSet) {
        c.panels.first
          ..keyCode = legacy.code
          ..keyName = legacy.name;
        await c.save();
      }
    }
    await NativeBridge.syncKeyBindings(c);
    if (!mounted) return;
    setState(() {
      _config = c;
      _urlCtrl.text = c.haUrl;
      _tokenCtrl.text = c.token;
    });
    if (reconnect) _ha.configure(c.haUrl, c.token, allowBadCertificates: c.allowBadCertificates);
  }

  Future<void> _refreshService() async {
    final on = await NativeBridge.isServiceEnabled();
    final auto = await NativeBridge.canAutoEnable();
    if (mounted) {
      setState(() {
        _serviceOn = on;
        _autoEnable = auto;
      });
    }
    // Wurde der Dienst gerade automatisch eingeschaltet, bindet Android ihn mit kurzer Verzoegerung.
    if (!on && auto) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final now = await NativeBridge.isServiceEnabled();
      if (mounted && now) setState(() => _serviceOn = true);
    }
  }

  Future<void> _save() async {
    await _config.save();
    await NativeBridge.syncKeyBindings(_config);
    _ha.configure(_config.haUrl, _config.token, allowBadCertificates: _config.allowBadCertificates);
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  // ---------------------------------------------------------------- HA im Netz suchen

  Future<void> _searchHa() async {
    final url = await showDialog<String>(context: context, builder: (_) => const _DiscoveryDialog());
    if (url == null || !mounted) return;
    setState(() => _urlCtrl.text = url);
    _config.haUrl = url;
    await _save();
    if (mounted && _config.token.isEmpty) {
      _snack('URL übernommen. Jetzt noch den Token eintragen (z. B. per Browser-Einrichtung).');
    }
  }

  // ---------------------------------------------------------------- Web-Einrichtung

  Future<void> _toggleWeb(bool on) async {
    if (on) {
      try {
        await _web.start();
        _webAddresses = await WebSetupServer.localAddresses();
      } catch (e) {
        _snack('Webserver konnte nicht starten: $e');
      }
    } else {
      await _web.stop();
    }
    setState(() {});
  }

  // ---------------------------------------------------------------- Panels

  Future<void> _openPanel(PanelConfig p) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PanelEditPage(ha: _ha, config: _config, panel: p, onChanged: _save),
    ));
    setState(() {});
  }

  Future<void> _addPanel() async {
    final p = PanelConfig('Panel ${_config.panels.length + 1}');
    setState(() => _config.panels.add(p));
    await _save();
    await _openPanel(p);
  }

  void _movePanel(int i, int delta) {
    setState(() => _config.panels.insert(i + delta, _config.panels.removeAt(i)));
    _save();
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: panelBackground,
        title: const Row(children: [
          Icon(Icons.home_rounded, color: brandGreen),
          SizedBox(width: 12),
          Text('Home Control'),
        ]),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _serviceSection(),
              _haSection(),
              _panelsSection(),
              _layoutSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _serviceSection() => SectionCard(title: 'Hintergrunddienst', icon: Icons.settings_remote, children: [
        StatusLine(
          ok: _serviceOn,
          text: _serviceOn
              ? 'Dienst läuft'
              : 'Dienst ist nicht aktiv – in den Bedienungshilfen „Home Control Panel“ einschalten.',
        ),
        const SizedBox(height: 8),
        StatusLine(
          ok: _autoEnable,
          text: _autoEnable
              ? 'Autostart abgesichert: Der Dienst schaltet sich nach Neustart, Update oder „Beenden erzwingen“ '
                  '(beim nächsten Öffnen der App) selbst wieder ein.'
              : 'Autostart nicht abgesichert. Einmalig am PC ausführen:\n'
                  'adb shell pm grant org.lotzapp.home_control android.permission.WRITE_SECURE_SETTINGS',
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: NativeBridge.openAccessibilitySettings,
            icon: const Icon(Icons.accessibility_new),
            label: const Text('Bedienungshilfen öffnen'),
          ),
        ),
      ]);

  Widget _haSection() {
    final (ok, text) = switch (_ha.status) {
      HaStatus.connected => (true, 'Verbunden${_ha.haVersion != null ? ' (HA ${_ha.haVersion})' : ''} · ${_ha.states.length} Entitäten'),
      HaStatus.connecting => (false, 'Verbinde…'),
      HaStatus.authFailed => (false, 'Token ungültig: ${_ha.error ?? ''}'),
      HaStatus.disconnected => (false, 'Nicht erreichbar: ${_ha.error ?? ''}'),
      HaStatus.notConfigured => (false, 'URL und Token eintragen'),
    };
    return SectionCard(title: 'Home Assistant', icon: Icons.hub, children: [
      StatusLine(ok: ok, text: text),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _urlCtrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'URL', hintText: 'http://192.168.1.10:8123'),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(onPressed: _searchHa, icon: const Icon(Icons.wifi_find), label: const Text('Suchen')),
      ]),
      const SizedBox(height: 12),
      TextField(
        controller: _tokenCtrl,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Long-Lived Access Token'),
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: _config.allowBadCertificates,
        onChanged: (v) => setState(() => _config.allowBadCertificates = v ?? false),
        title: const Text('Selbstsignierte Zertifikate erlauben'),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: () {
            _config.haUrl = HaClient.normalizeUrl(_urlCtrl.text);
            _config.token = _tokenCtrl.text.trim();
            _save();
          },
          icon: const Icon(Icons.link),
          label: const Text('Speichern & verbinden'),
        ),
      ),
      const Divider(height: 32),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _web.isRunning,
        onChanged: _toggleWeb,
        title: const Text('Einrichtung per Browser (Handy/PC)'),
        subtitle: Text(_web.isRunning
            ? 'Im Browser öffnen:\n${_webAddresses.join('\n')}'
            : 'Token, Panels und Gruppen bequem vom Handy eintragen'),
      ),
    ]);
  }

  Widget _panelsSection() {
    final panels = _config.panels;
    return SectionCard(title: 'Panels', icon: Icons.dashboard_customize, children: [
      const Text(
        'Jedes Panel hat eine eigene Taste. Kurz drücken öffnet das Panel, '
        'lang drücken löst die Lang-Drücken-Aktion aus.',
        style: TextStyle(color: Colors.white54),
      ),
      const SizedBox(height: 8),
      for (var i = 0; i < panels.length; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.dashboard, color: panels[i].keyCode != 0 ? brandGreen : Colors.white38),
          title: Text(panels[i].name),
          subtitle: Text(_panelSummary(panels[i])),
          onTap: () => _openPanel(panels[i]),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(onPressed: i > 0 ? () => _movePanel(i, -1) : null, icon: const Icon(Icons.arrow_upward)),
            IconButton(
                onPressed: i < panels.length - 1 ? () => _movePanel(i, 1) : null,
                icon: const Icon(Icons.arrow_downward)),
            IconButton(onPressed: () => _openPanel(panels[i]), icon: const Icon(Icons.chevron_right)),
          ]),
        ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(onPressed: _addPanel, icon: const Icon(Icons.add), label: const Text('Panel hinzufügen')),
      ),
    ]);
  }

  String _panelSummary(PanelConfig p) {
    final groups = p.items.whereType<GroupItem>().length;
    final entities = p.items.whereType<EntityItem>().length;
    final lp = p.longPress;
    return [
      p.keyCode != 0 ? 'Taste ${p.keyName}' : 'keine Taste',
      '$entities Entitäten, $groups Gruppen',
      if (lp != null) 'lang: ${_ha.states[lp.entityId]?.name ?? lp.entityId}',
    ].join(' · ');
  }

  Widget _layoutSection() => SectionCard(title: 'Darstellung', icon: Icons.tune, children: [
        StepperRow(
          label: 'Spalten',
          value: '${_config.columns}',
          onDec: _config.columns > 2 ? () => _set(() => _config.columns--) : null,
          onInc: _config.columns < 8 ? () => _set(() => _config.columns++) : null,
        ),
        StepperRow(
          label: 'Panelgröße',
          value: '${_config.panelPercent} %',
          onDec: _config.panelPercent > 40 ? () => _set(() => _config.panelPercent -= 5) : null,
          onInc: _config.panelPercent < 100 ? () => _set(() => _config.panelPercent += 5) : null,
        ),
        StepperRow(
          label: 'Automatisch schließen',
          value: _config.autoCloseSeconds == 0 ? 'nie' : 'nach ${_config.autoCloseSeconds} s',
          onDec: _config.autoCloseSeconds > 0 ? () => _set(() => _config.autoCloseSeconds -= 10) : null,
          onInc: _config.autoCloseSeconds < 300 ? () => _set(() => _config.autoCloseSeconds += 10) : null,
        ),
      ]);

  void _set(VoidCallback fn) {
    setState(fn);
    _save();
  }
}

/// Sucht Home Assistant im Netz und laesst eine gefundene Instanz auswaehlen.
class _DiscoveryDialog extends StatefulWidget {
  const _DiscoveryDialog();

  @override
  State<_DiscoveryDialog> createState() => _DiscoveryDialogState();
}

class _DiscoveryDialogState extends State<_DiscoveryDialog> {
  late Future<List<HaInstance>> _search = HaDiscovery.search();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.wifi_find, size: 40, color: brandGreen),
      title: const Text('Home Assistant suchen'),
      content: SizedBox(
        width: 480,
        child: FutureBuilder<List<HaInstance>>(
          future: _search,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(height: 8),
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Durchsuche das Netzwerk…'),
              ]);
            }
            final list = snap.data ?? [];
            if (list.isEmpty) {
              return const Text('Keine Home-Assistant-Instanz gefunden.\n'
                  'Ist das Gerät im selben Netz? Sonst die URL von Hand eintragen.');
            }
            return Column(mainAxisSize: MainAxisSize.min, children: [
              for (final (i, ha) in list.indexed)
                ListTile(
                  autofocus: i == 0,
                  leading: const Icon(Icons.home_rounded, color: brandGreen),
                  title: Text(ha.name),
                  subtitle: Text(ha.version == null ? ha.url : '${ha.url} · Version ${ha.version}'),
                  onTap: () => Navigator.of(context).pop(ha.url),
                ),
            ]);
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() => _search = HaDiscovery.search()),
          child: const Text('Erneut suchen'),
        ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
      ],
    );
  }
}
