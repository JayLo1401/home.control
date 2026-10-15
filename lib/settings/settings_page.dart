import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config.dart';
import '../core/native_bridge.dart';
import '../core/theme.dart';
import '../ha/ha_client.dart';
import '../ha/ha_discovery.dart';
import '../ha/ha_entity.dart';
import '../panel/quick_panel.dart';
import 'entity_picker_page.dart';
import 'web_setup_server.dart';

/// Tasten, die nicht als Ausloeser taugen (sonst ist die Navigation blockiert).
const _forbiddenKeys = {3, 4, 19, 20, 21, 22, 23, 66};

class SettingsPage extends StatefulWidget {
  final HaClient ha;
  const SettingsPage({super.key, required this.ha});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  AppConfig _config = AppConfig();
  bool _serviceOn = false;
  TriggerKey _trigger = const TriggerKey(0, '');
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
    _lifecycle = AppLifecycleListener(onResume: _refreshNative);
    _load(reconnect: true);
    _refreshNative();
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
    if (!mounted) return;
    setState(() {
      _config = c;
      _urlCtrl.text = c.haUrl;
      _tokenCtrl.text = c.token;
    });
    if (reconnect) _ha.configure(c.haUrl, c.token, allowBadCertificates: c.allowBadCertificates);
  }

  Future<void> _refreshNative() async {
    final on = await NativeBridge.isServiceEnabled();
    final key = await NativeBridge.getTriggerKey();
    if (mounted) {
      setState(() {
        _serviceOn = on;
        _trigger = key;
      });
    }
  }

  Future<void> _save() async {
    await _config.save();
    _ha.configure(_config.haUrl, _config.token, allowBadCertificates: _config.allowBadCertificates);
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  // ---------------------------------------------------------------- Taste anlernen

  Future<void> _learnKey() async {
    await _refreshNative();
    if (!mounted) return;
    if (!_serviceOn) {
      _snack('Zuerst den Hintergrunddienst in den Bedienungshilfen aktivieren.');
      return;
    }
    var learned = false;
    final dialog = showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(
        icon: Icon(Icons.settings_remote, size: 48),
        title: Text('Taste drücken'),
        content: Text(
          'Drücke jetzt auf der Fernbedienung die Taste, die das Panel öffnen soll.\n\n'
          'Hinweis: Diese Taste verliert danach ihre normale Funktion.',
        ),
      ),
    );
    unawaited(dialog.then((_) {
      if (!learned) NativeBridge.cancelLearn();
    }));
    try {
      final key = await NativeBridge.learnKey().timeout(const Duration(seconds: 20));
      learned = true;
      if (!mounted) return;
      Navigator.of(context).pop();
      if (_forbiddenKeys.contains(key.code)) {
        _snack('${key.name} kann nicht verwendet werden (wird zur Navigation gebraucht).');
        return;
      }
      await NativeBridge.setTriggerKey(key.code);
      await _refreshNative();
      _snack('Taste ${key.name} gespeichert.');
    } on TimeoutException {
      if (mounted) Navigator.of(context).pop();
      _snack('Keine Taste erkannt.');
    } on PlatformException catch (e) {
      if (mounted) Navigator.of(context).pop();
      _snack(e.message ?? 'Fehler');
    }
  }

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

  // ---------------------------------------------------------------- Entitaeten

  Future<void> _pickEntities() async {
    if (_ha.status != HaStatus.connected) {
      _snack('Erst mit Home Assistant verbinden.');
      return;
    }
    final result = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(builder: (_) => EntityPickerPage(ha: _ha, selected: _config.entities)),
    );
    if (result != null) {
      setState(() => _config.entities = result);
      await _save();
    }
  }

  void _move(int i, int delta) {
    final j = i + delta;
    if (j < 0 || j >= _config.entities.length) return;
    setState(() {
      final e = _config.entities.removeAt(i);
      _config.entities.insert(j, e);
    });
    _save();
  }

  void _openPreview() {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      pageBuilder: (_, _, _) => _PreviewPage(ha: _ha, config: _config),
    ));
  }

  Future<void> _testOverlay() async {
    if (!await NativeBridge.showOverlay()) {
      _snack('Hintergrunddienst ist nicht aktiv.');
    }
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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: OutlinedButton.icon(onPressed: _openPreview, icon: const Icon(Icons.preview), label: const Text('Vorschau')),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(onPressed: _testOverlay, icon: const Icon(Icons.layers), label: const Text('Overlay testen')),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _serviceSection(),
              _haSection(),
              _entitySection(),
              _layoutSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title, IconData icon, List<Widget> children) => Card(
        color: panelBackground,
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(icon, color: brandGreen),
                const SizedBox(width: 10),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
              ]),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );

  Widget _statusChip(bool ok, String okText, String badText) => Row(children: [
        Icon(ok ? Icons.check_circle : Icons.error, color: ok ? brandGreen : Colors.redAccent),
        const SizedBox(width: 8),
        Expanded(child: Text(ok ? okText : badText)),
      ]);

  Widget _serviceSection() => _section('Hintergrunddienst & Taste', Icons.settings_remote, [
        _statusChip(_serviceOn, 'Dienst läuft', 'Dienst ist nicht aktiv – in den Bedienungshilfen „Home Control Panel“ einschalten.'),
        const SizedBox(height: 8),
        _statusChip(
          _trigger.isSet,
          'Panel-Taste: ${_trigger.name} (Code ${_trigger.code})',
          'Noch keine Taste angelernt',
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, children: [
          OutlinedButton.icon(
            onPressed: NativeBridge.openAccessibilitySettings,
            icon: const Icon(Icons.accessibility_new),
            label: const Text('Bedienungshilfen öffnen'),
          ),
          FilledButton.icon(onPressed: _learnKey, icon: const Icon(Icons.keyboard), label: const Text('Taste anlernen')),
          if (_trigger.isSet)
            TextButton(
              onPressed: () async {
                await NativeBridge.setTriggerKey(0);
                _refreshNative();
              },
              child: const Text('Taste entfernen'),
            ),
        ]),
      ]);

  Widget _haSection() {
    final (ok, text) = switch (_ha.status) {
      HaStatus.connected => (true, 'Verbunden${_ha.haVersion != null ? ' (HA ${_ha.haVersion})' : ''} · ${_ha.states.length} Entitäten'),
      HaStatus.connecting => (false, 'Verbinde…'),
      HaStatus.authFailed => (false, 'Token ungültig: ${_ha.error ?? ''}'),
      HaStatus.disconnected => (false, 'Nicht erreichbar: ${_ha.error ?? ''}'),
      HaStatus.notConfigured => (false, 'URL und Token eintragen'),
    };
    return _section('Home Assistant', Icons.hub, [
      _statusChip(ok, text, text),
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
            : 'Token und Entitäten bequem vom Handy eintragen'),
      ),
    ]);
  }

  Widget _entitySection() => _section('Entitäten im Panel', Icons.grid_view_rounded, [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _pickEntities,
            icon: const Icon(Icons.playlist_add),
            label: const Text('Entitäten auswählen'),
          ),
        ),
        const SizedBox(height: 8),
        if (_config.entities.isEmpty) const Text('Noch keine Entitäten gewählt.', style: TextStyle(color: Colors.white54)),
        for (var i = 0; i < _config.entities.length; i++) _entityRow(i),
      ]);

  Widget _entityRow(int i) {
    final id = _config.entities[i];
    final e = _ha.states[id];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(e == null ? Icons.help_outline : iconFor(e)),
      title: Text(e?.name ?? id),
      subtitle: Text(e == null ? id : '$id · ${stateLabel(e)}'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(onPressed: i > 0 ? () => _move(i, -1) : null, icon: const Icon(Icons.arrow_upward)),
        IconButton(onPressed: i < _config.entities.length - 1 ? () => _move(i, 1) : null, icon: const Icon(Icons.arrow_downward)),
        IconButton(
          onPressed: () {
            setState(() => _config.entities.removeAt(i));
            _save();
          },
          icon: const Icon(Icons.close),
        ),
      ]),
    );
  }

  Widget _layoutSection() => _section('Darstellung', Icons.tune, [
        _stepper('Spalten', '${_config.columns}', () => _config.columns > 2, () => _config.columns--,
            () => _config.columns < 8, () => _config.columns++),
        _stepper('Panelgröße', '${_config.panelPercent} %', () => _config.panelPercent > 40, () => _config.panelPercent -= 5,
            () => _config.panelPercent < 100, () => _config.panelPercent += 5),
        _stepper(
            'Automatisch schließen',
            _config.autoCloseSeconds == 0 ? 'nie' : 'nach ${_config.autoCloseSeconds} s',
            () => _config.autoCloseSeconds > 0,
            () => _config.autoCloseSeconds -= 10,
            () => _config.autoCloseSeconds < 300,
            () => _config.autoCloseSeconds += 10),
      ]);

  Widget _stepper(String label, String value, bool Function() canDec, VoidCallback dec, bool Function() canInc,
          VoidCallback inc) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
          IconButton(
            onPressed: canDec() ? () => setState(() { dec(); _save(); }) : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(width: 120, child: Text(value, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16))),
          IconButton(
            onPressed: canInc() ? () => setState(() { inc(); _save(); }) : null,
            icon: const Icon(Icons.add),
          ),
        ]),
      );
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

/// Panel in der App – zum Testen auf Tablet (Touch) oder TV ohne Dienst.
class _PreviewPage extends StatelessWidget {
  final HaClient ha;
  final AppConfig config;
  _PreviewPage({required this.ha, required this.config});

  final _panel = GlobalKey<QuickPanelState>();

  static final _keys = {
    LogicalKeyboardKey.arrowUp: PanelKey.up,
    LogicalKeyboardKey.arrowDown: PanelKey.down,
    LogicalKeyboardKey.arrowLeft: PanelKey.left,
    LogicalKeyboardKey.arrowRight: PanelKey.right,
    LogicalKeyboardKey.select: PanelKey.select,
    LogicalKeyboardKey.enter: PanelKey.select,
    LogicalKeyboardKey.numpadEnter: PanelKey.select,
    LogicalKeyboardKey.gameButtonA: PanelKey.select,
    LogicalKeyboardKey.space: PanelKey.select,
  };

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyUpEvent) return KeyEventResult.ignored;
        final k = _keys[event.logicalKey];
        if (k == null) return KeyEventResult.ignored;
        _panel.currentState?.handleKey(k);
        return KeyEventResult.handled;
      },
      child: Material(
        type: MaterialType.transparency,
        child: QuickPanel(key: _panel, ha: ha, config: config, onClose: () => Navigator.of(context).maybePop()),
      ),
    );
  }
}
