import 'package:flutter/material.dart';

import '../ha/ha_client.dart';
import '../ha/ha_entity.dart';

/// Auswahl der Entitaeten aus allen Entitaeten von Home Assistant.
class EntityPickerPage extends StatefulWidget {
  final HaClient ha;
  final List<String> selected;

  /// Einzelauswahl: Antippen gibt sofort `[entityId]` zurueck.
  final bool single;

  /// Optionaler Filter (z. B. nur schaltbare Entitaeten).
  final bool Function(HaEntity)? filter;

  final String? title;

  const EntityPickerPage({
    super.key,
    required this.ha,
    this.selected = const [],
    this.single = false,
    this.filter,
    this.title,
  });

  @override
  State<EntityPickerPage> createState() => _EntityPickerPageState();
}

class _EntityPickerPageState extends State<EntityPickerPage> {
  static const _domains = [
    'light', 'switch', 'cover', 'scene', 'script', 'climate', 'fan', 'lock', 'media_player',
    'input_boolean', 'automation', 'button', 'sensor', 'binary_sensor', 'vacuum', 'person',
  ];

  late final List<String> _selected = [...widget.selected];
  String? _domain;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final all = widget.ha.states.values
        .where((e) => widget.filter == null || widget.filter!(e))
        .where((e) => _domain == null || e.domain == _domain)
        .where((e) =>
            _query.isEmpty ||
            e.entityId.toLowerCase().contains(_query) ||
            e.name.toLowerCase().contains(_query))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return PopScope(
      canPop: widget.single,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_selected);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title ?? (widget.single ? 'Entität wählen' : 'Entitäten wählen (${_selected.length})')),
          actions: [
            if (!widget.single)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(_selected),
                icon: const Icon(Icons.check),
                label: const Text('Fertig'),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Suchen…'),
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _chip('Alle', null),
                  for (final d in _domains) _chip(d, d),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: all.length,
                itemBuilder: (context, i) {
                  final e = all[i];
                  if (widget.single) {
                    return ListTile(
                      leading: Icon(iconFor(e)),
                      title: Text(e.name),
                      subtitle: Text('${e.entityId} · ${stateLabel(e)}'),
                      onTap: () => Navigator.of(context).pop([e.entityId]),
                    );
                  }
                  final on = _selected.contains(e.entityId);
                  return CheckboxListTile(
                    value: on,
                    secondary: Icon(iconFor(e)),
                    title: Text(e.name),
                    subtitle: Text('${e.entityId} · ${stateLabel(e)}'),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.add(e.entityId);
                      } else {
                        _selected.remove(e.entityId);
                      }
                    }),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String? domain) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: _domain == domain,
          onSelected: (_) => setState(() => _domain = domain),
        ),
      );
}
