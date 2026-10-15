import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/native_bridge.dart';
import '../core/theme.dart';
import '../ha/entity_look.dart';
import '../ha/ha_client.dart';
import '../ha/ha_entity.dart';
import '../panel/preview_page.dart';
import 'entity_customize.dart';
import 'entity_picker_page.dart';
import 'key_learning.dart';
import 'widgets.dart';

/// Ein Panel bearbeiten: Name, Taste, Lang-Druecken-Aktion, Inhalt (Entitaeten & Gruppen).
class PanelEditPage extends StatefulWidget {
  final HaClient ha;
  final AppConfig config;
  final PanelConfig panel;

  /// Speichert die Konfiguration (inkl. Tastenbelegung im Dienst).
  final Future<void> Function() onChanged;

  const PanelEditPage({super.key, required this.ha, required this.config, required this.panel, required this.onChanged});

  @override
  State<PanelEditPage> createState() => _PanelEditPageState();
}

class _PanelEditPageState extends State<PanelEditPage> {
  late final _nameCtrl = TextEditingController(text: widget.panel.name);

  PanelConfig get _p => widget.panel;
  HaClient get _ha => widget.ha;

  @override
  void initState() {
    super.initState();
    _ha.addListener(_rebuild);
  }

  @override
  void dispose() {
    _ha.removeListener(_rebuild);
    _nameCtrl.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _change(VoidCallback fn) {
    setState(fn);
    widget.onChanged();
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  bool _requireConnection() {
    if (_ha.status == HaStatus.connected) return true;
    _snack('Erst mit Home Assistant verbinden.');
    return false;
  }

  // ---------------------------------------------------------------- Taste

  Future<void> _learn() async {
    final key = await learnKeyDialog(context);
    if (key == null || !mounted) return;
    final other = widget.config.panels.where((p) => p != _p && p.keyCode == key.code).firstOrNull;
    if (other != null) {
      _snack('${key.name} ist schon „${other.name}“ zugeordnet.');
      return;
    }
    _change(() {
      _p.keyCode = key.code;
      _p.keyName = key.name;
    });
    _snack('Taste ${key.name} gespeichert.');
  }

  // ---------------------------------------------------------------- Lang druecken

  Future<void> _pickLongPressEntity() async {
    if (!_requireConnection()) return;
    final result = await Navigator.of(context).push<List<String>>(MaterialPageRoute(
      builder: (_) => EntityPickerPage(
        ha: _ha,
        single: true,
        title: 'Aktion bei langem Drücken',
        filter: (e) => primaryAction(e) != null || e.domain == 'scene' || e.domain == 'script',
      ),
    ));
    if (result == null || result.isEmpty) return;
    _change(() {
      final lp = _p.longPress;
      if (lp == null) {
        _p.longPress = LongPressAction(result.first);
      } else {
        lp.entityId = result.first;
      }
    });
  }

  // ---------------------------------------------------------------- Inhalt

  Future<void> _customize(String id) async {
    if (await showEntityCustomizeDialog(context, widget.config, _ha, id)) _change(() {});
  }

  Future<void> _addEntities() async {
    if (!_requireConnection()) return;
    final current = [for (final i in _p.items) if (i is EntityItem) i.entityId];
    final result = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(builder: (_) => EntityPickerPage(ha: _ha, selected: current)),
    );
    if (result == null) return;
    _change(() {
      // Abgewaehlte einzelne Entitaeten entfernen, neue hinten anhaengen; Gruppen bleiben.
      _p.items.removeWhere((i) => i is EntityItem && !result.contains(i.entityId));
      for (final id in result.where((id) => !current.contains(id))) {
        _p.items.add(EntityItem(id));
      }
    });
  }

  Future<void> _addGroup() async {
    final name = await _askName(context, 'Neue Gruppe', '');
    if (name == null || name.isEmpty || !mounted) return;
    final group = GroupItem(name);
    _change(() => _p.items.add(group));
    await _editGroup(group);
  }

  Future<void> _editGroup(GroupItem g) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GroupEditPage(ha: _ha, config: widget.config, group: g, onChanged: widget.onChanged),
    ));
    setState(() {});
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('„${_p.name}“ löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    widget.config.panels.remove(_p);
    await widget.onChanged();
    if (mounted) Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final index = widget.config.panels.indexOf(_p);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: panelBackground,
        title: Text(_p.name),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(PageRouteBuilder(
                opaque: false,
                pageBuilder: (_, _, _) => PreviewPage(ha: _ha, config: widget.config, panel: _p),
              )),
              icon: const Icon(Icons.preview),
              label: const Text('Vorschau'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: () async {
                if (!await NativeBridge.showOverlay(panelIndex: index)) _snack('Hintergrunddienst ist nicht aktiv.');
              },
              icon: const Icon(Icons.layers),
              label: const Text('Overlay testen'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline), tooltip: 'Panel löschen'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [_generalSection(), _longPressSection(), _contentSection()],
          ),
        ),
      ),
    );
  }

  Widget _generalSection() => SectionCard(title: 'Panel', icon: Icons.dashboard_customize, children: [
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(labelText: 'Name'),
          onChanged: (v) => _change(() => _p.name = v.trim().isEmpty ? 'Panel' : v.trim()),
        ),
        const SizedBox(height: 12),
        StatusLine(ok: _p.keyCode != 0, text: _p.keyCode != 0 ? 'Taste: ${_p.keyName}' : 'Noch keine Taste angelernt'),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, children: [
          FilledButton.icon(onPressed: _learn, icon: const Icon(Icons.keyboard), label: const Text('Taste anlernen')),
          if (_p.keyCode != 0)
            TextButton(
              onPressed: () => _change(() {
                _p.keyCode = 0;
                _p.keyName = '';
              }),
              child: const Text('Taste entfernen'),
            ),
        ]),
      ]);

  Widget _longPressSection() {
    final lp = _p.longPress;
    final e = lp == null ? null : _ha.states[lp.entityId];
    return SectionCard(title: 'Lang drücken', icon: Icons.touch_app, children: [
      if (lp == null) ...[
        const Text('Keine Aktion. Lang drücken öffnet dann ebenfalls das Panel.',
            style: TextStyle(color: Colors.white54)),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _pickLongPressEntity,
            icon: const Icon(Icons.add),
            label: const Text('Aktion festlegen'),
          ),
        ),
      ] else ...[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(entityIcon(widget.config, lp.entityId, e)),
          title: Text(entityName(widget.config, lp.entityId, e)),
          subtitle: Text(entitySubtitle(widget.config, lp.entityId, e)),
          trailing: TextButton(onPressed: _pickLongPressEntity, child: const Text('Ändern')),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'toggle', label: Text('Umschalten'), icon: Icon(Icons.swap_horiz)),
            ButtonSegment(value: 'on', label: Text('Einschalten'), icon: Icon(Icons.power)),
            ButtonSegment(value: 'off', label: Text('Ausschalten'), icon: Icon(Icons.power_off)),
          ],
          selected: {lp.mode},
          onSelectionChanged: (s) => _change(() => lp.mode = s.first),
        ),
        const SizedBox(height: 8),
        StepperRow(
          label: 'Haltedauer',
          value: '${(lp.holdMs / 1000).toStringAsFixed(1)} s',
          onDec: lp.holdMs > 1000 ? () => _change(() => lp.holdMs -= 500) : null,
          onInc: lp.holdMs < 6000 ? () => _change(() => lp.holdMs += 500) : null,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _change(() => _p.longPress = null),
            icon: const Icon(Icons.close),
            label: const Text('Aktion entfernen'),
          ),
        ),
      ],
    ]);
  }

  Widget _contentSection() {
    final items = _p.items;
    return SectionCard(title: 'Inhalt', icon: Icons.grid_view_rounded, children: [
      Wrap(spacing: 12, runSpacing: 12, children: [
        FilledButton.icon(onPressed: _addEntities, icon: const Icon(Icons.playlist_add), label: const Text('Entitäten')),
        FilledButton.tonalIcon(onPressed: _addGroup, icon: const Icon(Icons.create_new_folder), label: const Text('Gruppe')),
      ]),
      const SizedBox(height: 8),
      if (items.isEmpty) const Text('Noch leer.', style: TextStyle(color: Colors.white54)),
      for (var i = 0; i < items.length; i++) _itemRow(items, i),
    ]);
  }

  Widget _itemRow(List<PanelItem> items, int i) {
    final item = items[i];
    final up = i > 0 ? () => _change(() => items.insert(i - 1, items.removeAt(i))) : null;
    final down = i < items.length - 1 ? () => _change(() => items.insert(i + 1, items.removeAt(i))) : null;
    void remove() => _change(() => items.removeAt(i));
    switch (item) {
      case EntityItem(:final entityId):
        final e = _ha.states[entityId];
        return ReorderRow(
          leading: Icon(entityIcon(widget.config, entityId, e)),
          title: entityName(widget.config, entityId, e),
          subtitle: entitySubtitle(widget.config, entityId, e),
          onUp: up,
          onDown: down,
          onEdit: () => _customize(entityId),
          onRemove: remove,
        );
      case GroupItem():
        final names = [for (final id in item.entities) entityName(widget.config, id, _ha.states[id])];
        return ReorderRow(
          leading: const Icon(Icons.workspaces, color: brandGreen),
          title: 'Gruppe: ${item.name}',
          subtitle: names.isEmpty ? 'leer' : names.join(', '),
          onUp: up,
          onDown: down,
          onEdit: () => _editGroup(item),
          onRemove: remove,
        );
    }
  }
}

/// Gruppe bearbeiten: Name und Entitaeten (Sensoren erscheinen als Wert auf der Kachel).
class GroupEditPage extends StatefulWidget {
  final HaClient ha;
  final GroupItem group;
  final Future<void> Function() onChanged;

  final AppConfig config;

  const GroupEditPage({
    super.key,
    required this.ha,
    required this.config,
    required this.group,
    required this.onChanged,
  });

  @override
  State<GroupEditPage> createState() => _GroupEditPageState();
}

class _GroupEditPageState extends State<GroupEditPage> {
  late final _nameCtrl = TextEditingController(text: widget.group.name);

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _change(VoidCallback fn) {
    setState(fn);
    widget.onChanged();
  }

  /// Ein Sensorfeld der Ueberschrift: anzeigen, waehlen, entfernen.
  Widget _sensorSlot(String label, IconData icon, String? current, String deviceClass, List<String> units,
      void Function(String?) set) {
    final e = current == null ? null : widget.ha.states[current];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: accentAmber),
      title: Text(label),
      subtitle: Text(current == null
          ? 'nicht zugeordnet'
          : '${entityName(widget.config, current, e)} · ${e == null ? current : stateLabel(e)}'),
      onTap: () => _pickSensor(label, deviceClass, units, set),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          onPressed: () => _pickSensor(label, deviceClass, units, set),
          icon: Icon(current == null ? Icons.add : Icons.edit),
        ),
        if (current != null) IconButton(onPressed: () => _change(() => set(null)), icon: const Icon(Icons.close)),
      ]),
    );
  }

  Future<void> _pickSensor(String label, String deviceClass, List<String> units, void Function(String?) set) async {
    if (widget.ha.status != HaStatus.connected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erst mit Home Assistant verbinden.')));
      return;
    }
    final result = await Navigator.of(context).push<List<String>>(MaterialPageRoute(
      builder: (_) => EntityPickerPage(
        ha: widget.ha,
        single: true,
        title: '$label für „${widget.group.name}“',
        filter: (e) => e.domain == 'sensor' && (e.deviceClass == deviceClass || units.contains(e.unit)),
      ),
    ));
    if (result != null && result.isNotEmpty) _change(() => set(result.first));
  }

  Future<void> _addEntities() async {
    if (widget.ha.status != HaStatus.connected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erst mit Home Assistant verbinden.')));
      return;
    }
    final result = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(builder: (_) => EntityPickerPage(ha: widget.ha, selected: widget.group.entities)),
    );
    if (result == null) return;
    _change(() => widget.group.entities = mergeSelection(widget.group.entities, result));
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.group.entities;
    return Scaffold(
      appBar: AppBar(backgroundColor: panelBackground, title: Text('Gruppe: ${widget.group.name}')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            SectionCard(title: 'Gruppe', icon: Icons.workspaces, children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
                onChanged: (v) => _change(() => widget.group.name = v.trim().isEmpty ? 'Gruppe' : v.trim()),
              ),
              const SizedBox(height: 8),
              const Text(
                'Die Gruppe erscheint im Panel als Überschrift mit den Kacheln darunter.',
                style: TextStyle(color: Colors.white54),
              ),
            ]),
            SectionCard(title: 'Werte in der Überschrift', icon: Icons.sensors, children: [
              _sensorSlot('Temperatur', Icons.thermostat, widget.group.temperature, 'temperature', const ['°C', '°F'],
                  (v) => widget.group.temperature = v),
              _sensorSlot('Luftfeuchtigkeit', Icons.water_drop, widget.group.humidity, 'humidity', const ['%'],
                  (v) => widget.group.humidity = v),
              _sensorSlot('Stromverbrauch', Icons.bolt, widget.group.power, 'power', const ['W', 'kW'],
                  (v) => widget.group.power = v),
            ]),
            SectionCard(title: 'Entitäten', icon: Icons.list, children: [
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _addEntities,
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Entitäten auswählen'),
                ),
              ),
              const SizedBox(height: 8),
              if (list.isEmpty) const Text('Noch leer.', style: TextStyle(color: Colors.white54)),
              for (var i = 0; i < list.length; i++)
                entityRow(widget.ha, widget.config, list, i, _change, onEdit: () async {
                  if (await showEntityCustomizeDialog(context, widget.config, widget.ha, list[i])) _change(() {});
                }),
            ]),
          ]),
        ),
      ),
    );
  }
}

Future<String?> _askName(BuildContext context, String title, String initial) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name', hintText: 'z. B. Whirlpool'),
        onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}
