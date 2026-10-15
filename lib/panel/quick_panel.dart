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
class _Section {
  final GroupItem? group;
  final List<String> tiles;
  _Section(this.group, this.tiles);
}

/// Seitenverhaeltnis der (flachen) Kacheln.
const _tileAspect = 2.5;

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
          result.add(_Section(item, item.entities));
      }
    }
    return result;
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
                    borderRadius: BorderRadius.circular(20 * scale),
                    border: Border.all(color: brandGreen.withValues(alpha: 0.6), width: 2),
                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 40)],
                  ),
                  padding: EdgeInsets.fromLTRB(14 * scale, 10 * scale, 14 * scale, 10 * scale),
                  child: Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _header(context, scale),
                          SizedBox(height: 6 * scale),
                          Expanded(child: _body(context, scale)),
                        ],
                      ),
                      _messageToast(scale),
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

  /// Schmale Kopfzeile: Panelname, Verbindung, Uhrzeit.
  Widget _header(BuildContext context, double s) {
    final now = DateTime.now();
    final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final (color, text) = switch (widget.ha.status) {
      HaStatus.connected => (brandGreen, null),
      HaStatus.connecting => (accentAmber, 'Verbinde…'),
      HaStatus.authFailed => (Colors.redAccent, 'Token ungültig'),
      HaStatus.notConfigured => (Colors.grey, 'Nicht eingerichtet'),
      HaStatus.disconnected => (Colors.redAccent, 'Getrennt'),
    };
    return Row(
      children: [
        Icon(Icons.home_rounded, color: brandGreen, size: 20 * s),
        SizedBox(width: 8 * s),
        // Expanded (nicht Flexible + Spacer): schiebt Status und Uhr ganz nach rechts.
        Expanded(
          child: Text(
            widget.panel?.name ?? 'Home Control',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 16 * s, fontWeight: FontWeight.w600, color: Colors.white70),
          ),
        ),
        Container(
          width: 8 * s,
          height: 8 * s,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        if (text != null) ...[
          SizedBox(width: 6 * s),
          Text(text, style: TextStyle(fontSize: 13 * s, color: Colors.white70)),
        ],
        SizedBox(width: 14 * s),
        Text(time, style: TextStyle(fontSize: 16 * s, color: Colors.white70)),
      ],
    );
  }

  /// Kurze Meldung (z. B. Fehler) – nur bei Bedarf eingeblendet, braucht keinen festen Platz.
  Widget _messageToast(double s) => Positioned(
        left: 0,
        right: 0,
        bottom: 4 * s,
        child: IgnorePointer(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _message == null
                ? const SizedBox.shrink()
                : Center(
                    key: ValueKey(_message),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 8 * s),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(20 * s),
                        border: Border.all(color: accentAmber),
                      ),
                      child: Text(_message!, style: TextStyle(fontSize: 14 * s, color: accentAmber)),
                    ),
                  ),
          ),
        ),
      );

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
    final gap = 10 * s;
    // Rand innerhalb des Scrollbereichs, damit die vergroesserte Auswahl samt Leuchten nicht abgeschnitten wird.
    final edge = 8 * s;
    var index = 0;
    final slivers = <Widget>[];
    for (final (si, section) in sections.indexed) {
      if (section.group != null) {
        slivers.add(SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: edge),
          sliver: SliverToBoxAdapter(
            child: GroupHeader(group: section.group!, ha: widget.ha, scale: s, first: si == 0),
          ),
        ));
      } else if (si > 0) {
        // Lose Kacheln nach einer Gruppe: eigene (namenlose) Trennlinie,
        // damit sie nicht wie ein Teil der Gruppe darueber wirken.
        slivers.add(SliverPadding(
          padding: EdgeInsets.fromLTRB(edge, 14 * s, edge, 4 * s),
          sliver: SliverToBoxAdapter(child: Divider(height: 1, thickness: 1.5, color: Colors.white24)),
        ));
      }
      final start = index;
      index += section.tiles.length;
      if (section.tiles.isEmpty) continue;
      slivers.add(SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: edge, vertical: edge / 2),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _cols,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            childAspectRatio: _tileAspect,
          ),
          delegate: SliverChildBuilderDelegate(
            childCount: section.tiles.length,
            (context, k) {
              final i = start + k;
              final id = section.tiles[k];
              final e = widget.ha.states[id];
              return GestureDetector(
                key: _tileKeys.putIfAbsent(i, GlobalKey.new),
                onTap: () {
                  setState(() => _selected = i);
                  _restartIdle();
                  _toggleEntity(id);
                },
                child: EntityTile(
                  entity: e,
                  name: entityName(widget.config, id, e),
                  icon: entityIcon(widget.config, id, e),
                  selected: i == _selected,
                  busy: _busy.contains(id),
                ),
              );
            },
          ),
        ),
      ));
    }
    slivers.add(SliverToBoxAdapter(child: SizedBox(height: edge)));
    return CustomScrollView(slivers: slivers);
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
}

/// Gruppenueberschrift: Name + Temperatur, Luftfeuchte, Leistung (soweit zugeordnet).
class GroupHeader extends StatelessWidget {
  final GroupItem group;
  final HaClient ha;
  final double scale;
  final bool first;

  const GroupHeader({super.key, required this.group, required this.ha, required this.scale, this.first = false});

  /// Wert eines Sensors fuer die Ueberschrift, `null` wenn nicht gesetzt/verfuegbar.
  String? _value(String? id, int decimals, String fallbackUnit) {
    final e = id == null ? null : ha.states[id];
    if (e == null || e.isUnavailable) return null;
    final v = formatNumber(e.state, decimals: decimals);
    if (v == null) return null;
    return '$v ${e.unit ?? fallbackUnit}';
  }

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final values = [
      (Icons.thermostat, _value(group.temperature, 1, '°C')),
      (Icons.water_drop, _value(group.humidity, 0, '%')),
      (Icons.bolt, _value(group.power, 0, 'W')),
    ].where((v) => v.$2 != null);
    final valueStyle = TextStyle(fontSize: 17 * s, fontWeight: FontWeight.w400, color: Colors.white);

    return Padding(
      padding: EdgeInsets.only(top: first ? 2 * s : 14 * s, bottom: 4 * s),
      child: Container(
        padding: EdgeInsets.only(bottom: 4 * s),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: brandGreen.withValues(alpha: 0.5), width: 1.5)),
        ),
        child: Row(
          children: [
            Flexible(
              child: Text(
                group.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 18 * s, fontWeight: FontWeight.w700, color: brandGreen),
              ),
            ),
            for (final (icon, text) in values) ...[
              SizedBox(width: 18 * s),
              Icon(icon, size: 18 * s, color: accentAmber),
              SizedBox(width: 4 * s),
              Text(text!, style: valueStyle),
            ],
          ],
        ),
      ),
    );
  }
}

/// Flache Kachel: Symbol + Name. Zustand ueber die Farbe; reine Anzeige-
/// Entitaeten (z. B. Sensoren) zeigen zusaetzlich ihren Wert.
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
    // Zweite Zeile nur fuer Anzeige-Entitaeten und "nicht verfuegbar".
    final showValue = e == null || primaryAction(e) == null;
    final iconColor = unavailable ? Colors.white24 : (active ? accentAmber : Colors.white70);
    final focus = Theme.of(context).focusColor;

    // Schrift/Icon an die Kachelgroesse anpassen (mehr Spalten -> kleinere Kacheln).
    return LayoutBuilder(builder: (context, c) {
      // 6 = Fokusrahmen (skaliert nicht mit)
      final s = min((c.maxWidth - 6) / 200, (c.maxHeight - 6) / 74).clamp(0.25, 2.0);
      return AnimatedScale(
        scale: selected ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
          decoration: BoxDecoration(
            color: active ? Color.lerp(tileBackground, accentAmber, 0.16) : tileBackground,
            borderRadius: BorderRadius.circular(12 * s),
            border: Border.all(
              color: selected ? focus : (active ? accentAmber.withValues(alpha: 0.5) : Colors.white10),
              width: selected ? 3 : 1,
            ),
            boxShadow:
                selected ? [BoxShadow(color: focus.withValues(alpha: 0.5), blurRadius: 12, spreadRadius: 1)] : null,
          ),
          child: Row(
            children: [
              busy
                  ? SizedBox(
                      width: 26 * s,
                      height: 26 * s,
                      child: Padding(
                        padding: EdgeInsets.all(4 * s),
                        child: const CircularProgressIndicator(strokeWidth: 2, color: accentAmber),
                      ),
                    )
                  : Icon(icon, color: iconColor, size: 26 * s),
              SizedBox(width: 10 * s),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: showValue ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15 * s,
                        fontWeight: FontWeight.w600,
                        color: unavailable ? Colors.white54 : Colors.white,
                        height: 1.15,
                      ),
                    ),
                    if (showValue)
                      Text(
                        e == null ? 'Nicht gefunden' : stateLabel(e),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14 * s, color: unavailable ? Colors.white38 : accentAmber),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
