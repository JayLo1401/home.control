import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../ha/ha_client.dart';
import '../ha/ha_entity.dart';

class SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const SectionCard({super.key, required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) => Card(
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
}

class StatusLine extends StatelessWidget {
  final bool ok;
  final String text;
  const StatusLine({super.key, required this.ok, required this.text});

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(ok ? Icons.check_circle : Icons.error, color: ok ? brandGreen : Colors.redAccent),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ]);
}

/// Zeile einer sortierbaren Liste: ↑ ↓ (✎) ✕
class ReorderRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onEdit;
  final VoidCallback onRemove;

  const ReorderRow({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.onUp,
    this.onDown,
    this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: leading,
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        onTap: onEdit,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (onEdit != null) IconButton(onPressed: onEdit, icon: const Icon(Icons.edit)),
          IconButton(onPressed: onUp, icon: const Icon(Icons.arrow_upward)),
          IconButton(onPressed: onDown, icon: const Icon(Icons.arrow_downward)),
          IconButton(onPressed: onRemove, icon: const Icon(Icons.close)),
        ]),
      );
}

/// Zeile fuer eine einzelne Entitaet in einer sortierbaren Liste.
ReorderRow entityRow(HaClient ha, List<String> list, int i, void Function(VoidCallback) change) {
  final id = list[i];
  final e = ha.states[id];
  return ReorderRow(
    leading: Icon(e == null ? Icons.help_outline : iconFor(e)),
    title: e?.name ?? id,
    subtitle: e == null ? id : '$id · ${stateLabel(e)}',
    onUp: i > 0 ? () => change(() => list.insert(i - 1, list.removeAt(i))) : null,
    onDown: i < list.length - 1 ? () => change(() => list.insert(i + 1, list.removeAt(i))) : null,
    onRemove: () => change(() => list.removeAt(i)),
  );
}

/// Behaelt die Reihenfolge vorhandener Eintraege, entfernt abgewaehlte, haengt neue an.
List<String> mergeSelection(List<String> old, List<String> picked) => [
      ...old.where(picked.contains),
      ...picked.where((p) => !old.contains(p)),
    ];

/// Plus/Minus-Einstellung (D-Pad-freundlicher als ein Slider).
class StepperRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onDec;
  final VoidCallback? onInc;

  const StepperRow({super.key, required this.label, required this.value, this.onDec, this.onInc});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
          IconButton(onPressed: onDec, icon: const Icon(Icons.remove)),
          SizedBox(width: 120, child: Text(value, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16))),
          IconButton(onPressed: onInc, icon: const Icon(Icons.add)),
        ]),
      );
}
