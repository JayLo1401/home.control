import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../ha/entity_look.dart';
import '../ha/ha_client.dart';
import '../ha/ha_entity.dart';

enum PanelKey { up, down, left, right, select }

/// Abschnitt im Panel: lose Entitaeten (ohne Ueberschrift) oder eine Gruppe.
/// Sensoren einer Gruppe erscheinen als Wert in der Ueberschrift, nicht als Kachel.
class _Section {
  final GroupItem? group;
  final List<String> tiles;
  _Section(this.group, this.tiles);
}

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
  /// Index in der flachen Kachelliste ueber alle Abschnitte.
  int _selected = 0;

  final _tileKeys = <int, GlobalKey>{};
  final _busy = <String>{};
  Timer? _idleTimer;
  Timer? _clockTimer;
  String? _message;
  Timer? _messageTimer;

  int get _cols => widget.config.columns;

  List<_Section> get _sections {
    final result = <_Section>[];
    _Section? loose;
    for (final item in widget.panel?.items ?? const <PanelItem>[]) {
      switch (item) {
        case EntityItem(:final entityId):
          if (loose == null) {
            loose = _Section(null, []);
            result.add(loose);
          }
          loose.tiles.add(entityId);
        case GroupItem():
          loose = null;
          result.add(_Section(item, [
            for (final id in item.entities)
              if (!_isSensorId(id)) id,
          ]));
      }
    }
    return result;
  }

  bool _isSensorId(String id) {
    final e = widget.ha.states[id];
    return e != null ? isSensor(e) : id.startsWith('sensor.') || id.startsWith('weather.');
  }

  /// Kacheln als Zeilen (flache Indizes) – fuer Hoch/Runter ueber Abschnitte hinweg.
  List<List<int>> _rows(List<_Section> sections) {
    final rows = <List<int>>[];
    var index = 0;
    for (final s in sections) {
      for (var i = 0; i < s.tiles.length; i += _cols) {
        final n = min(_cols, s.tiles.length - i);
        rows.add([for (var k = 0; k < n; k++) index + k]);
        index += n;
      }
    }
    return rows;
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

  /// Zurueck-Taste: `false` = Panel schliessen.
  bool handleBack() => false;

  void handleKey(PanelKey key) {
    _restartIdle();
    final sections = _sections;
    final tiles = [for (final s in sections) ...s.tiles];
    final n = tiles.length;
    if (n == 0) return;
    final cur = _selected.clamp(0, n - 1);
    var i = cur;
    switch (key) {
      case PanelKey.left:
        i = cur > 0 ? cur - 1 : n - 1;
      case PanelKey.right:
        i = cur < n - 1 ? cur + 1 : 0;
      case PanelKey.up:
      case PanelKey.down:
        final rows = _rows(sections);
        final r = rows.indexWhere((row) => row.contains(cur));
        final target = r + (key == PanelKey.up ? -1 : 1);
        if (target >= 0 && target < rows.length) {
          final col = rows[r].indexOf(cur);
          final row = rows[target];
          i = row[min(col, row.length - 1)];
        }
      case PanelKey.select:
        _toggleEntity(tiles[cur]);
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

  Future<void> _toggleEntity(String id) async {
    final e = widget.ha.states[id];
    if (e == null) return;
    final name = entityName(widget.config, id, e);
    final action = primaryAction(e);
    if (action == null) {
      _showMessage('$name: ${stateLabel(e)}');
      return;
    }
    setState(() => _busy.add(id));
    try {
      await widget.ha.callService(action.domain, action.service, entityId: id);
      if (e.domain == 'scene' || e.domain == 'script' || e.domain == 'button' || e.domain == 'input_button') {
        _showMessage('$name ausgeführt');
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
    return Row(
      children: [
        Icon(Icons.home_rounded, color: brandGreen, size: 32 * s),
        SizedBox(width: 12 * s),
        Flexible(
          child: Text(
            widget.panel?.name ?? 'Home Control',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 24 * s, fontWeight: FontWeight.w600),
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
    final sections = _sections;
    if (sections.isEmpty) {
      return _hint(s, Icons.playlist_add, 'Hier ist noch nichts eingetragen.\nÖffne die App „Home Control“.');
    }
    final gap = 14 * s;
    var index = 0;
    final slivers = <Widget>[];
    for (final (si, section) in sections.indexed) {
      if (section.group != null) {
        slivers.add(SliverToBoxAdapter(
          child: GroupHeader(group: section.group!, ha: widget.ha, scale: s, first: si == 0),
        ));
      } else if (si > 0) {
        slivers.add(SliverToBoxAdapter(child: SizedBox(height: gap)));
      }
      final start = index;
      index += section.tiles.length;
      if (section.tiles.isEmpty) continue;
      slivers.add(SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _cols,
          mainAxisSpacing: gap,
          crossAxisSpacing: gap,
          childAspectRatio: 1.55,
        ),
        delegate: SliverChildBuilderDelegate(
          childCount: section.tiles.length,
          (context, k) {
            final i = start + k;
            final id = section.tiles[k];
            return GestureDetector(
              key: _tileKeys.putIfAbsent(i, GlobalKey.new),
              onTap: () {
                setState(() => _selected = i);
                _restartIdle();
                _toggleEntity(id);
              },
              child: EntityTile(
                entity: widget.ha.states[id],
                name: entityName(widget.config, id, widget.ha.states[id]),
                icon: entityIcon(widget.config, id, widget.ha.states[id]),
                selected: i == _selected,
                busy: _busy.contains(id),
              ),
            );
          },
        ),
      ));
    }
    return Padding(
      padding: EdgeInsets.all(8 * s),
      child: CustomScrollView(slivers: slivers),
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
    const hint = '◀ ▲ ▼ ▶  auswählen   ·   OK  schalten   ·   Zurück  schließen';
    return SizedBox(
      height: 22 * s,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _message != null
            ? Text(_message!, key: const ValueKey('msg'), style: style.copyWith(color: accentAmber), textAlign: TextAlign.center)
            : Text(hint, key: const ValueKey('hint'), style: style, textAlign: TextAlign.center),
      ),
    );
  }
}

/// Gruppenueberschrift: Name und Sensorwerte, z. B. "Whirlpool   35 °C · 40 %".
class GroupHeader extends StatelessWidget {
  final GroupItem group;
  final HaClient ha;
  final double scale;
  final bool first;

  const GroupHeader({super.key, required this.group, required this.ha, required this.scale, this.first = false});

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final values = [
      for (final id in group.entities)
        if (ha.states[id] case final e? when isSensor(e) && !e.isUnavailable) stateLabel(e),
    ];
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 22 * s, bottom: 10 * s),
      child: Container(
        padding: EdgeInsets.only(bottom: 6 * s),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: brandGreen.withValues(alpha: 0.5), width: 1.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                group.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 20 * s, fontWeight: FontWeight.w700, color: brandGreen),
              ),
            ),
            if (values.isNotEmpty) ...[
              SizedBox(width: 16 * s),
              Flexible(
                child: Text(
                  values.join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 20 * s, fontWeight: FontWeight.w300, color: Colors.white),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EntityTile extends StatelessWidget {
  final HaEntity? entity;
  final String name;
  final IconData icon;
  final bool selected;
  final bool busy;

  const EntityTile({
    super.key,
    required this.entity,
    required this.name,
    required this.icon,
    required this.selected,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    final e = entity;
    final active = e != null && isActive(e);
    final unavailable = e == null || e.isUnavailable;
    final iconColor = unavailable ? Colors.white24 : (active ? accentAmber : Colors.white70);
    final focus = Theme.of(context).focusColor;

    // Schrift/Icon an die Kachelgroesse anpassen (mehr Spalten -> kleinere Kacheln).
    return LayoutBuilder(builder: (context, c) {
      // 6 = Fokusrahmen oben+unten (skaliert nicht mit)
      final s = min((c.maxWidth - 6) / 190, (c.maxHeight - 6) / 122).clamp(0.25, 2.0);
      return AnimatedScale(
        scale: selected ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.all(12 * s),
          decoration: BoxDecoration(
            color: active ? Color.lerp(tileBackground, accentAmber, 0.14) : tileBackground,
            borderRadius: BorderRadius.circular(16 * s),
            border: Border.all(color: selected ? focus : Colors.white10, width: selected ? 3 : 1),
            boxShadow:
                selected ? [BoxShadow(color: focus.withValues(alpha: 0.5), blurRadius: 14, spreadRadius: 1)] : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: iconColor, size: 32 * s),
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
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16 * s,
                  fontWeight: FontWeight.w600,
                  color: unavailable ? Colors.white54 : Colors.white,
                  height: 1.15,
                ),
              ),
              SizedBox(height: 3 * s),
              Text(
                e == null ? 'Nicht gefunden' : stateLabel(e),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13 * s, color: active ? accentAmber : Colors.white60),
              ),
            ],
          ),
        ),
      );
    });
  }
}
