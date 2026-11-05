import 'package:flutter/material.dart';

import '../core/update_service.dart';
import 'widgets.dart';

/// Einstellungen → Verbindung → Updates: installierte Version, automatische
/// Updates (laufen im Hintergrunddienst), von Hand suchen und installieren.
class UpdateSection extends StatefulWidget {
  const UpdateSection({super.key});

  @override
  State<UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends State<UpdateSection> {
  String _version = '';
  bool _auto = true;
  bool _canInstall = true;
  bool _checking = false;
  bool _checked = false;
  double? _progress;
  bool _installing = false;
  AvailableUpdate? _update;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Nach dem Erlauben in den Systemeinstellungen neu pruefen.
    _lifecycle = AppLifecycleListener(onResume: _refreshPermission);
    _init();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final (name, _) = await UpdateService.currentVersion();
    final auto = await UpdateService.autoUpdate();
    if (!mounted) return;
    setState(() {
      _version = name;
      _auto = auto;
    });
    if (UpdateService.supported) {
      await _refreshPermission();
      await _check();
    }
  }

  Future<void> _refreshPermission() async {
    final can = await UpdateService.canInstall();
    if (mounted) setState(() => _canInstall = can);
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final update = await UpdateService.check();
    if (!mounted) return;
    setState(() {
      _update = update;
      _checking = false;
      _checked = true;
    });
  }

  Future<void> _install(AvailableUpdate update) async {
    setState(() {
      _installing = true;
      _progress = null;
    });
    try {
      await UpdateService.install(update, onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      _snack('Update auf ${update.version} wird installiert…');
    } on UpdateException catch (e) {
      _snack('Update fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  Future<void> _openPermission() async {
    if (!await UpdateService.openInstallPermission()) {
      _snack('Keine Einstellungsseite gefunden – einmalig am PC ausführen:\n$_adbHint');
    }
  }

  static const _adbHint = 'adb shell appops set at.jaycloud.home.control REQUEST_INSTALL_PACKAGES allow';

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    const hint = TextStyle(color: Colors.white54);
    final update = _update;
    return SectionCard(title: 'Updates', icon: Icons.system_update, children: [
      Text('Installierte Version: ${_version.isEmpty ? '…' : _version}'),
      const SizedBox(height: 8),
      if (!UpdateService.supported)
        const Text('Diese Version wurde lokal gebaut und aktualisiert sich nicht selbst.', style: hint)
      else ...[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Automatisch aktualisieren'),
          subtitle: const Text(
            'Der Hintergrunddienst sucht alle 6 Stunden nach neuen Versionen und installiert sie, '
            'wenn kein Panel offen ist.',
            style: hint,
          ),
          value: _auto,
          onChanged: (v) {
            setState(() => _auto = v);
            UpdateService.setAutoUpdate(v);
          },
        ),
        if (!_canInstall) ...[
          const StatusLine(
            ok: false,
            text: 'Die App darf noch keine Updates installieren. „Unbekannte Apps installieren“ für Home Control '
                'erlauben – oder einmalig am PC:\n$_adbHint',
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _openPermission,
              icon: const Icon(Icons.security),
              label: const Text('Berechtigung erteilen'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        if (_installing)
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_progress == null ? 'Wird geladen…' : 'Wird geladen… ${(_progress! * 100).round()} %'),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _progress),
          ])
        else if (_checking)
          const Row(children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Suche nach Updates…'),
          ])
        else if (update != null)
          Row(children: [
            Expanded(child: Text('Neue Version ${update.version} verfügbar.')),
            FilledButton.icon(
              onPressed: _canInstall ? () => _install(update) : null,
              icon: const Icon(Icons.system_update),
              label: const Text('Jetzt aktualisieren'),
            ),
          ])
        else
          Row(children: [
            Expanded(
              child: Text(_checked ? 'Die App ist aktuell (oder der Update-Server ist nicht erreichbar).' : ''),
            ),
            OutlinedButton.icon(
              onPressed: _check,
              icon: const Icon(Icons.refresh),
              label: const Text('Erneut suchen'),
            ),
          ]),
      ],
    ]);
  }
}
