import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../ha/entity_look.dart';
import '../ha/ha_client.dart';
import '../ha/ha_entity.dart';

/// Eigenen Namen und eigenes Symbol fuer eine Entitaet festlegen.
/// Gibt `true` zurueck, wenn etwas geaendert wurde.
Future<bool> showEntityCustomizeDialog(BuildContext context, AppConfig config, HaClient ha, String id) async {
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => _CustomizeDialog(config: config, ha: ha, id: id),
  );
  return changed ?? false;
}

class _CustomizeDialog extends StatefulWidget {
  final AppConfig config;
  final HaClient ha;
  final String id;

  const _CustomizeDialog({required this.config, required this.ha, required this.id});

  @override
  State<_CustomizeDialog> createState() => _CustomizeDialogState();
}

class _CustomizeDialogState extends State<_CustomizeDialog> {
  late final _nameCtrl = TextEditingController(text: widget.config.overrides[widget.id]?.name ?? '');
  late String? _icon = widget.config.overrides[widget.id]?.icon;

  HaEntity? get _e => widget.ha.states[widget.id];

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickIcon() async {
    final picked = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const IconPickerPage()));
    if (picked != null) setState(() => _icon = picked);
  }

  @override
  Widget build(BuildContext context) {
    final haIcon = _e?.attributes['icon'] as String?;
    final preview = mdiIcon(_icon) ?? mdiIcon(haIcon) ?? (_e == null ? Icons.help_outline : iconFor(_e!));
    final iconSource = _icon != null
        ? 'Eigenes Symbol ($_icon)'
        : haIcon != null
            ? 'Symbol aus Home Assistant ($haIcon)'
            : 'Standardsymbol';

    return AlertDialog(
      title: Text(_e?.name ?? widget.id),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.id, style: const TextStyle(color: Colors.white54)),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Eigener Name',
              hintText: _e?.name ?? widget.id,
              helperText: 'Leer lassen = Name aus Home Assistant',
            ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: tileBackground, borderRadius: BorderRadius.circular(12)),
              child: Icon(preview, size: 36, color: accentAmber),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(iconSource, style: const TextStyle(color: Colors.white70))),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 8, children: [
            FilledButton.tonalIcon(onPressed: _pickIcon, icon: const Icon(Icons.emoji_symbols), label: const Text('Symbol wählen')),
            if (_icon != null)
              TextButton(onPressed: () => setState(() => _icon = null), child: const Text('Symbol zurücksetzen')),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: () {
            widget.config.setOverride(widget.id, name: _nameCtrl.text, icon: _icon);
            Navigator.of(context).pop(true);
          },
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

/// Haeufige Symbole fuers Haus (MDI-Namen wie in Home Assistant).
const _commonIcons = [
  'home', 'sofa', 'bed', 'television', 'lightbulb', 'lightbulb-group', 'ceiling-light', 'floor-lamp',
  'lamp', 'led-strip-variant', 'string-lights', 'outdoor-lamp', 'wall-sconce', 'desk-lamp',
  'power-socket-eu', 'power', 'toggle-switch', 'fan', 'air-conditioner', 'radiator', 'fireplace',
  'thermometer', 'water-percent', 'hot-tub', 'pool', 'shower', 'water', 'water-pump', 'pump',
  'sprinkler', 'watering-can', 'flower', 'tree', 'grill', 'umbrella-beach', 'table-chair',
  'garage', 'gate', 'door', 'door-open', 'window-closed', 'window-open', 'blinds', 'roller-shade',
  'curtains', 'lock', 'lock-open', 'cctv', 'doorbell', 'bell', 'alarm-light', 'shield-home',
  'speaker', 'music', 'play-circle', 'movie-open', 'projector', 'gamepad-variant', 'robot-vacuum',
  'washing-machine', 'tumble-dryer', 'dishwasher', 'fridge', 'stove', 'coffee-maker', 'kettle',
  'car', 'car-electric', 'ev-station', 'solar-power', 'battery', 'flash', 'weather-sunny',
  'weather-night', 'palette', 'party-popper', 'cabin-a-frame', 'home-outline', 'warehouse', 'sauna',
];

/// Symbolauswahl: Haeufige Symbole oder Suche in allen MDI-Symbolen.
class IconPickerPage extends StatefulWidget {
  const IconPickerPage({super.key});

  @override
  State<IconPickerPage> createState() => _IconPickerPageState();
}

class _IconPickerPageState extends State<IconPickerPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final all = Mdi.icons;
    final names = _query.isEmpty
        ? _commonIcons.where(all.containsKey).toList()
        : all.keys.where((n) => n.contains(_query)).take(400).toList();

    return Scaffold(
      appBar: AppBar(backgroundColor: panelBackground, title: const Text('Symbol wählen')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Suchen (englisch, z. B. pool, sofa, lamp, pump)…',
            ),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase().replaceAll(' ', '-')),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _query.isEmpty ? 'Häufige Symbole' : '${names.length} Treffer${names.length == 400 ? ' (gekürzt)' : ''}',
              style: const TextStyle(color: Colors.white54),
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 110,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: names.length,
            itemBuilder: (context, i) => _IconCell(name: names[i], icon: all[names[i]]!),
          ),
        ),
      ]),
    );
  }
}

class _IconCell extends StatefulWidget {
  final String name;
  final IconData icon;
  const _IconCell({required this.name, required this.icon});

  @override
  State<_IconCell> createState() => _IconCellState();
}

class _IconCellState extends State<_IconCell> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return TvFocusHighlight(
      focused: _focused,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onFocusChange: (f) => setState(() => _focused = f),
        onTap: () => Navigator.of(context).pop('mdi:${widget.name}'),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(widget.icon, size: 36),
          const SizedBox(height: 6),
          Text(
            widget.name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Colors.white60),
          ),
        ]),
      ),
    );
  }
}
