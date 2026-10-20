import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/backup.dart';
import '../core/config.dart';
import 'widgets.dart';

/// Sicherung in Download/HomeControl anlegen oder wiederherstellen. Die Liste
/// wird beim Zurueckkehren in die App neu geladen, damit sie "Zugriff auf alle
/// Dateien" gleich nach dem Erlauben in den Systemeinstellungen beruecksichtigt.
class BackupSection extends StatefulWidget {
  final AppConfig config;

  /// Wiederhergestellte Konfiguration speichern und uebernehmen.
  final Future<void> Function(AppConfig restored) onRestore;

  const BackupSection({super.key, required this.config, required this.onRestore});

  @override
  State<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<BackupSection> {
  List<BackupFile> _backups = const [];
  bool _canRequestAllFiles = false;
  bool _busy = false;
  String? _error;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () {
      if (!_busy) _reload();
    });
    _reload();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final backups = await Backup.list();
      final canRequest = await Backup.canRequestAllFilesAccess();
      if (!mounted) return;
      setState(() {
        _backups = backups;
        _canRequestAllFiles = canRequest;
        _error = null;
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _backups = const [];
        _error = e.code == 'PERMISSION_DENIED'
            ? 'Ohne Speicher-Berechtigung können keine Sicherungen gelesen werden.'
            : 'Sicherungen konnten nicht gelesen werden (${e.message}).';
      });
    }
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      _snack('Gesichert: ${await Backup.create(widget.config)}');
    } on PlatformException catch (e) {
      _snack(e.code == 'PERMISSION_DENIED'
          ? 'Ohne Speicher-Berechtigung kann nicht gesichert werden.'
          : 'Sicherung fehlgeschlagen: ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _reload();
  }

  Future<bool> _confirm(String what) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sicherung wiederherstellen?'),
          content: Text('$what\n\nURL, Token, Panels, Tasten, Darstellung und Türglocke werden ersetzt.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Wiederherstellen'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _restore(Future<AppConfig?> Function() load) async {
    setState(() => _busy = true);
    try {
      final c = await load();
      if (c == null) return;
      await widget.onRestore(c);
      _snack('Sicherung wiederhergestellt ✔');
    } on FormatException catch (e) {
      _snack(e.message);
    } on PlatformException catch (e) {
      _snack(e.code == 'NO_PICKER'
          ? 'Dieses Gerät hat keine Dateiauswahl. Bitte „Zugriff auf alle Dateien“ erlauben.'
          : 'Wiederherstellen fehlgeschlagen: ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreFile(BackupFile f) async {
    if (await _confirm(f.name)) await _restore(() => Backup.read(f));
  }

  Future<void> _restorePicked() async {
    if (await _confirm('Die ausgewählte Datei wird eingespielt.')) await _restore(Backup.pick);
  }

  Future<void> _requestAllFiles() async {
    if (!await Backup.requestAllFilesAccess()) {
      _snack('Dieses Gerät bietet „Zugriff auf alle Dateien“ nicht an.');
    }
  }

  static String _date(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)}.${t.year}, ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    const hint = TextStyle(color: Colors.white54);
    return SectionCard(title: 'Sicherung', icon: Icons.save, children: [
      const Text(
        'Komplette Konfiguration inkl. Token, Tasten und Türglocken-Anmeldung. '
        'Wird unter „Download/HomeControl“ gespeichert und bleibt auch nach dem Deinstallieren der App erhalten.',
        style: hint,
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: _busy ? null : _create,
          icon: const Icon(Icons.save_alt),
          label: const Text('Jetzt sichern'),
        ),
      ),
      if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
      const Divider(height: 32),
      if (_error != null)
        Text(_error!, style: hint)
      else if (_backups.isEmpty)
        const Text('Keine Sicherungen gefunden.', style: hint)
      else
        for (final b in _backups)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.restore),
            title: Text(_date(b.modified)),
            subtitle: Text(b.name),
            onTap: _busy ? null : () => _restoreFile(b),
          ),
      if (_canRequestAllFiles) ...[
        const SizedBox(height: 8),
        const Text(
          'Sicherungen einer früheren Installation erscheinen erst, wenn „Zugriff auf alle Dateien“ erlaubt ist. '
          'Alternativ die Datei direkt auswählen.',
          style: hint,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _requestAllFiles,
            icon: const Icon(Icons.folder_open),
            label: const Text('Zugriff auf alle Dateien erlauben'),
          ),
        ),
      ],
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _busy ? null : _restorePicked,
          icon: const Icon(Icons.file_open),
          label: const Text('Sicherungsdatei auswählen …'),
        ),
      ),
    ]);
  }
}
