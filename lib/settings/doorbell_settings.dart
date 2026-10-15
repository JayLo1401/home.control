import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config.dart';
import '../core/native_bridge.dart';
import '../core/theme.dart';
import '../ha/ha_client.dart';
import '../ha/mobile_app.dart';
import 'widgets.dart';

/// Reiter "Tuerglocke": Anmeldung in HA als mobile_app-Geraet, Gong, Test, YAML-Beispiel.
class DoorbellSettings extends StatefulWidget {
  final HaClient ha;
  final AppConfig config;
  final Future<void> Function() onChanged;

  const DoorbellSettings({super.key, required this.ha, required this.config, required this.onChanged});

  @override
  State<DoorbellSettings> createState() => _DoorbellSettingsState();
}

class _DoorbellSettingsState extends State<DoorbellSettings> {
  final _nameCtrl = TextEditingController();
  Map<String, String> _device = {};
  bool _busy = false;

  DoorbellConfig get _d => widget.config.doorbell;

  @override
  void initState() {
    super.initState();
    _initName();
  }

  Future<void> _initName() async {
    _device = await NativeBridge.deviceInfo();
    if (!mounted) return;
    setState(() => _nameCtrl.text = _d.deviceName.isNotEmpty ? _d.deviceName : 'Home Control ${_device['model'] ?? 'TV'}');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  void _change(VoidCallback fn) {
    setState(fn);
    widget.onChanged();
  }

  Future<void> _register() async {
    final c = widget.config;
    if (widget.ha.status != HaStatus.connected) {
      _snack('Erst unter „Verbindung“ mit Home Assistant verbinden.');
      return;
    }
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      _d.deviceId ??= newDeviceId();
      final reg = await registerMobileApp(
        ha: widget.ha,
        url: c.haUrl,
        token: c.token,
        deviceId: _d.deviceId!,
        deviceName: name,
        device: _device,
        allowBadCertificates: c.allowBadCertificates,
      );
      _change(() {
        _d
          ..webhookId = reg.webhookId
          ..deviceName = name
          ..notifyService = reg.notifyService;
      });
      _snack(reg.notifyService != null
          ? 'Angemeldet: notify.${reg.notifyService}'
          : 'Angemeldet. Den notify-Dienst bitte in HA unter Entwicklerwerkzeuge → Aktionen suchen.');
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testViaHa() async {
    final service = _d.notifyService;
    if (service == null) return;
    try {
      await widget.ha.callService('notify', service, data: {
        'title': 'Türglocke',
        'message': 'Test über Home Assistant',
      });
    } catch (e) {
      _snack('Fehler: $e');
    }
  }

  String get _yaml {
    final service = _d.notifyService ?? 'mobile_app_${haSlug(_nameCtrl.text)}';
    return '''- action: notify.$service
  data:
    title: Türglocke
    message: Es hat an der Haustür geläutet
    data:
      duration: 30              # Sekunden sichtbar (optional)
      camera: camera.haustuer   # Kamerabild anzeigen (optional)''';
  }

  @override
  Widget build(BuildContext context) {
    final registered = _d.isRegistered;
    return ListView(padding: const EdgeInsets.all(16), children: [
      SectionCard(title: 'Anmeldung in Home Assistant', icon: Icons.notifications_active, children: [
        const Text(
          'Home Control meldet sich über die Integration „mobile_app“ als Gerät in Home Assistant an. '
          'Danach gibt es dort einen eigenen Benachrichtigungsdienst. Ruft eine Automation ihn auf, '
          'erscheint die Meldung mit Gong über allem, was gerade läuft. Die Musik wird dabei nur kurz leiser.',
          style: TextStyle(color: Colors.white54),
        ),
        const SizedBox(height: 12),
        StatusLine(
          ok: registered,
          text: registered
              ? 'Angemeldet als „${_d.deviceName}“${_d.notifyService != null ? ' · notify.${_d.notifyService}' : ''}'
              : 'Noch nicht angemeldet',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Gerätename in Home Assistant',
            helperText: 'Bestimmt den Dienstnamen, z. B. notify.mobile_app_home_control_wohnzimmer',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, children: [
          FilledButton.icon(
            onPressed: _busy ? null : _register,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.app_registration),
            label: Text(registered ? 'Neu anmelden' : 'Bei Home Assistant anmelden'),
          ),
          if (registered)
            TextButton(
              onPressed: () => _change(() {
                _d
                  ..webhookId = null
                  ..notifyService = null;
              }),
              child: const Text('Abmelden'),
            ),
        ]),
        if (registered) ...[
          const SizedBox(height: 8),
          const Text(
            'Abmelden trennt nur die App. Das Gerät selbst in HA unter Einstellungen → Geräte → Mobile App entfernen.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ]),
      SectionCard(title: 'Gong & Anzeige', icon: Icons.music_note, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _d.chime,
          onChanged: (v) => _change(() => _d.chime = v),
          title: const Text('Gong abspielen'),
          subtitle: const Text('Andere Wiedergabe wird dabei kurz leiser und läuft danach normal weiter'),
        ),
        StepperRow(
          label: 'Gong wiederholen',
          value: '${_d.chimeRepeat}×',
          onDec: _d.chimeRepeat > 1 ? () => _change(() => _d.chimeRepeat--) : null,
          onInc: _d.chimeRepeat < 5 ? () => _change(() => _d.chimeRepeat++) : null,
        ),
        StepperRow(
          label: 'Gong-Lautstärke',
          value: '${_d.volumePercent} %',
          onDec: _d.volumePercent > 10 ? () => _change(() => _d.volumePercent -= 10) : null,
          onInc: _d.volumePercent < 100 ? () => _change(() => _d.volumePercent += 10) : null,
        ),
        StepperRow(
          label: 'Meldung anzeigen',
          value: '${_d.durationSeconds} s',
          onDec: _d.durationSeconds > 10 ? () => _change(() => _d.durationSeconds -= 5) : null,
          onInc: _d.durationSeconds < 300 ? () => _change(() => _d.durationSeconds += 5) : null,
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 12, children: [
          OutlinedButton.icon(
            onPressed: () async {
              if (!await NativeBridge.testDoorbell()) _snack('Hintergrunddienst ist nicht aktiv.');
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('Test (lokal)'),
          ),
          if (_d.notifyService != null)
            FilledButton.tonalIcon(
              onPressed: _testViaHa,
              icon: const Icon(Icons.hub),
              label: const Text('Test über Home Assistant'),
            ),
        ]),
      ]),
      SectionCard(title: 'In der Automation', icon: Icons.code, children: [
        const Text(
          'Diese Aktion in die Türglocken-Automation einfügen, am besten als erste Aktion (vor das Lichtsignal):',
          style: TextStyle(color: Colors.white54),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
          child: SelectableText(_yaml, style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: accentAmber)),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _yaml));
              _snack('YAML kopiert');
            },
            icon: const Icon(Icons.copy),
            label: const Text('Kopieren'),
          ),
        ),
        const Text(
          'Mit message: clear_notification wird die Meldung vorzeitig geschlossen (z. B. wenn die Tür geöffnet wird).',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ]),
    ]);
  }
}
