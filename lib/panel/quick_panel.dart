import 'dart:async';

import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../ha/ha_client.dart';
import '../ha/ha_entity.dart';

enum PanelKey { up, down, left, right, select }

/// Das Schnellzugriffs-Panel. Wird im Overlay (Tasten kommen vom Dienst) und
/// als Vorschau in der App (Tasten kommen vom Flutter-Fokus) verwendet.
class QuickPanel extends StatefulWidget {
  final HaClient ha;
  final AppConfig config;
  final PanelConfig? panel;
  final VoidCallback onClose;

  const QuickPanel({super.key, required this.ha, required this.config, required this.panel, required this.onClose});

  @override
  State<QuickPanel> createState() => QuickPanelState();
}

class QuickPanelState extends State<QuickPanel> {
  int _selected = 0;

  /// Geoeffnete Gruppe (null = Panel-Uebersicht) und Auswahl in der Uebersicht.
  GroupItem? _group;
  int _rootSelected = 0;

  final _tileKeys = <int, GlobalKey>{};
  final _busy = <String>{};
  Timer? _idleTimer;
  Timer? _clockTimer;
  String? _message;
  Timer? _messageTimer;

  /// Aktuell angezeigte Kacheln.
  List<PanelItem> get _items {
    final g = _group;
    if (g != null) return [for (final id in g.entities) EntityItem(id)];
    return widget.panel?.items ?? const [];
  }

  @override
  void initState() {
    super.initState();
    widget.ha.addListener(_onHa);
    _restartIdle();
    _clockTimer = Timer.periodic(const Duration(seconds: 20), (_) => setState(() {}));
  }

  @override
  void didUpdateWidget(QuickPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ha != widget.ha) {
      oldWidget.ha.removeListener(_onHa);
      widget.ha.addListener(_onHa);
    }
    if (oldWidget.panel != widget.panel) _group = null;
    if (_selected >= _items.length) _selected = 0;
  }

  @override
  void dispose() {
    widget.ha.removeListener(_onHa);
    _idleTimer?.cancel();
    _clockTimer?.cancel();
    _messageTimer?.cancel();
    super.dispose();
  }

  void _onHa() {
    if (mounted) setState(() {});
  }

  void _restartIdle() {
    _idleTimer?.cancel();
    final s = widget.config.autoCloseSeconds;
    if (s > 0) _idleTimer = Timer(Duration(seconds: s), widget.onClose);
  }

  /// Zurueck-Taste: Gruppe verlassen. `false` = Panel schliessen.
  bool handleBack() {
    _restartIdle();
    if (_group == null) return false;
    setState(() {
      _group = null;
      _selected = _rootSelected;
    });
    _scrollToSelected();
    return true;
  }

  void handleKey(PanelKey key) {
    _restartIdle();
    final n = _items.length;
    if (n == 0) return;
    final cols = widget.config.columns;
    var i = _selected;
    switch (key) {
      case PanelKey.left:
        i = i > 0 ? i - 1 : n - 1;
      case PanelKey.right:
        i = i < n - 1 ? i + 1 : 0;
      case PanelKey.up:
        if (i - cols >= 0) i -= cols;
      case PanelKey.down:
        if (i + cols < n) {
          i += cols;
        } else if (i ~/ cols < (n - 1) ~/ cols) {
          i = n - 1; // letzte, unvollstaendige Zeile
        }
      case PanelKey.select:
        _activate(i);
        return;
    }
    if (i != _selected) {
      setState(() => _selected = i);
      _scrollToSelected();
    }
  }

  void _scrollToSelected() {
    final i = _selected;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _tileKeys[i]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 150), alignment: 0.5);
      }
    });
  }

  Future<void> _activate(int index) async {
    final item = _items[index];
    switch (item) {
      case GroupItem():
        setState(() {
          _rootSelected = index;
          _group = item;
          _selected = 0;
        });
        _scrollToSelected();
      case EntityItem(:final entityId):
        await _toggleEntity(entityId);
    }
  }

  Future<void> _toggleEntity(String id) async {
    final e = widget.ha.states[id];
    if (e == null) return;
    final action = primaryAction(e);
    if (action == null) {
      _showMessage('${e.name}: ${stateLabel(e)}');
      return;
    }
    setState(() => _busy.add(id));
    try {
      await widget.ha.callService(action.domain, action.service, entityId: id);
      if (e.domain == 'scene' || e.domain == 'script' || e.domain == 'button' || e.domain == 'input_button') {
        _showMessage('${e.name} ausgeführt');
      }
    } catch (err) {
      _showMessage('Fehler: $err');
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  void _showMessage(String m) {
    _messageTimer?.cancel();
    setState(() => _message = m);
    _messageTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _message = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pct = widget.config.panelPercent / 100;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onClose,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.45),
        child: Center(
          child: FractionallySizedBox(
            widthFactor: pct,
            heightFactor: pct,
            child: GestureDetector(
              onTap: () {}, // Taps im Panel schliessen nicht
              child: LayoutBuilder(builder: (context, c) {
                final scale = (c.maxWidth / 800).clamp(0.8, 1.8);
                return Container(
                  decoration: BoxDecoration(
                    color: panelBackground.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(24 * scale),
                    border: Border.all(color: brandGreen.withValues(alpha: 0.6), width: 2),
                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 40)],
                  ),
                  padding: EdgeInsets.all(20 * scale),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(context, scale),
                      SizedBox(height: 16 * scale),
                      Expanded(child: _body(context, scale)),
                      SizedBox(height: 12 * scale),
                      _footer(scale),
                    ],
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, double s) {
    final now = DateTime.now();
    final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final (color, text) = switch (widget.ha.status) {
      HaStatus.connected => (brandGreen, 'Verbunden'),
      HaStatus.connecting => (accentAmber, 'Verbinde…'),
      HaStatus.authFailed => (Colors.redAccent, 'Token ungültig'),
      HaStatus.notConfigured => (Colors.grey, 'Nicht eingerichtet'),
      HaStatus.disconnected => (Colors.redAccent, 'Getrennt'),
    };
    final titleStyle = TextStyle(fontSize: 24 * s, fontWeight: FontWeight.w600);
    return Row(
      children: [
        Icon(_group == null ? Icons.home_rounded : Icons.workspaces, color: brandGreen, size: 32 * s),
        SizedBox(width: 12 * s),
        Flexible(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: widget.panel?.name ?? 'Home Control',
                style: _group == null ? titleStyle : titleStyle.copyWith(color: Colors.white54, fontWeight: FontWeight.w400),
              ),
              if (_group != null) ...[
                TextSpan(text: '  ›  ', style: titleStyle.copyWith(color: Colors.white38)),
                TextSpan(text: _group!.name, style: titleStyle),
              ],
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const Spacer(),
        Container(
          width: 10 * s,
          height: 10 * s,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: 8 * s),
        Text(text, style: TextStyle(fontSize: 15 * s, color: Colors.white70)),
        SizedBox(width: 24 * s),
        Text(time, style: TextStyle(fontSize: 24 * s, fontWeight: FontWeight.w300)),
      ],
    );
  }

  Widget _body(BuildContext context, double s) {
    if (!widget.config.isConfigured) {
      return _hint(s, Icons.settings, 'Home Assistant ist noch nicht eingerichtet.\nÖffne die App „Home Control“.');
    }
    if (widget.panel == null) {
      return _hint(s, Icons.dashboard_customize, 'Für diese Taste ist kein Panel eingerichtet.');
    }
    final items = _items;
    if (items.isEmpty) {
      return _hint(s, Icons.playlist_add, 'Hier ist noch nichts eingetragen.\nÖffne die App „Home Control“.');
    }
    final cols = widget.config.columns;
    return GridView.builder(
      key: ValueKey(_group), // Scrollposition je Ebene
      padding: EdgeInsets.all(8 * s),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 14 * s,
        crossAxisSpacing: 14 * s,
        childAspectRatio: 1.55,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        final key = _tileKeys.putIfAbsent(i, GlobalKey.new);
        return GestureDetector(
          key: key,
          onTap: () {
            setState(() => _selected = i);
            _restartIdle();
            _activate(i);
          },
          child: switch (item) {
            EntityItem(:final entityId) => EntityTile(
                id: entityId,
                entity: widget.ha.states[entityId],
                selected: i == _selected,
                busy: _busy.contains(entityId),
                scale: s,
              ),
            GroupItem() => GroupTile(group: item, ha: widget.ha, selected: i == _selected, scale: s),
          },
        );
      },
    );
  }

  Widget _hint(double s, IconData icon, String text) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56 * s, color: Colors.white38),
            SizedBox(height: 16 * s),
            Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 20 * s, color: Colors.white70)),
          ],
        ),
      );

  Widget _footer(double s) {
    final style = TextStyle(fontSize: 14 * s, color: Colors.white54);
    final hint = _group == null
        ? '◀ ▲ ▼ ▶  auswählen   ·   OK  schalten / öffnen   ·   Zurück  schließen'
        : '◀ ▲ ▼ ▶  auswählen   ·   OK  schalten   ·   Zurück  zur Übersicht';
    return SizedBox(
      height: 22 * s,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _message != null
            ? Text(_message!, key: const ValueKey('msg'), style: style.copyWith(color: accentAmber), textAlign: TextAlign.center)
            : Text(hint, key: ValueKey(hint), style: style, textAlign: TextAlign.center),
      ),
    );
  }
}

/// Gemeinsamer Kachelrahmen (Fokusrahmen, Hervorhebung bei "aktiv").
class _TileFrame extends StatelessWidget {
  final bool selected;
  final bool active;
  final double scale;
  final Widget child;

  const _TileFrame({required this.selected, required this.active, required this.scale, required this.child});

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final focus = Theme.of(context).focusColor;
    return AnimatedScale(
      scale: selected ? 1.05 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.all(14 * s),
        decoration: BoxDecoration(
          color: active ? Color.lerp(tileBackground, accentAmber, 0.14) : tileBackground,
          borderRadius: BorderRadius.circular(16 * s),
          border: Border.all(color: selected ? focus : Colors.white10, width: selected ? 3 : 1),
          boxShadow: selected ? [BoxShadow(color: focus.withValues(alpha: 0.5), blurRadius: 14, spreadRadius: 1)] : null,
        ),
        child: child,
      ),
    );
  }
}

class EntityTile extends StatelessWidget {
  final String id;
  final HaEntity? entity;
  final bool selected;
  final bool busy;
  final double scale;

  const EntityTile({
    super.key,
    required this.id,
    required this.entity,
    required this.selected,
    required this.busy,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final e = entity;
    final active = e != null && isActive(e);
    final unavailable = e == null || e.isUnavailable;
    final iconColor = unavailable ? Colors.white24 : (active ? accentAmber : Colors.white70);

    return _TileFrame(
      selected: selected,
      active: active,
      scale: s,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(e == null ? Icons.help_outline : iconFor(e), color: iconColor, size: 34 * s),
              const Spacer(),
              if (busy)
                SizedBox(
                  width: 18 * s,
                  height: 18 * s,
                  child: const CircularProgressIndicator(strokeWidth: 2, color: accentAmber),
                ),
            ],
          ),
          const Spacer(),
          Text(
            e?.name ?? id,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 17 * s,
              fontWeight: FontWeight.w600,
              color: unavailable ? Colors.white54 : Colors.white,
              height: 1.15,
            ),
          ),
          SizedBox(height: 4 * s),
          Text(
            e == null ? 'Nicht gefunden' : stateLabel(e),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14 * s, color: active ? accentAmber : Colors.white60),
          ),
        ],
      ),
    );
  }
}

/// Gruppenkachel: Sensorwerte gross, darunter was gerade an/offen ist.
class GroupTile extends StatelessWidget {
  final GroupItem group;
  final HaClient ha;
  final bool selected;
  final double scale;

  const GroupTile({super.key, required this.group, required this.ha, required this.selected, required this.scale});

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final entities = [for (final id in group.entities) ?ha.states[id]];
    final sensorValues = [
      for (final e in entities)
        if (isSensor(e) && !e.isUnavailable) stateLabel(e),
    ];
    final activeNames = [
      for (final e in entities)
        if (!isSensor(e) && isActive(e)) e.name,
    ];
    final active = activeNames.isNotEmpty;
    final status = active
        ? 'An: ${activeNames.join(', ')}'
        : (entities.any((e) => !isSensor(e)) ? 'Alles aus' : '${group.entities.length} Einträge');

    return _TileFrame(
      selected: selected,
      active: active,
      scale: s,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.workspaces, color: active ? accentAmber : brandGreen, size: 30 * s),
              SizedBox(width: 10 * s),
              Expanded(
                child: Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18 * s, fontWeight: FontWeight.w700),
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.white38, size: 24 * s),
            ],
          ),
          const Spacer(),
          if (sensorValues.isNotEmpty)
            Text(
              sensorValues.join('  ·  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 24 * s, fontWeight: FontWeight.w300, height: 1.1),
            ),
          SizedBox(height: 4 * s),
          Text(
            status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14 * s, color: active ? accentAmber : Colors.white60),
          ),
        ],
      ),
    );
  }
}
