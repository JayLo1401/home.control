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
  final VoidCallback onClose;

  const QuickPanel({super.key, required this.ha, required this.config, required this.onClose});

  @override
  State<QuickPanel> createState() => QuickPanelState();
}

class QuickPanelState extends State<QuickPanel> {
  int _selected = 0;
  final _tileKeys = <int, GlobalKey>{};
  final _busy = <String>{};
  Timer? _idleTimer;
  Timer? _clockTimer;
  String? _message;
  Timer? _messageTimer;

  List<String> get _ids => widget.config.entities;

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
    if (_selected >= _ids.length) _selected = 0;
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

  void handleKey(PanelKey key) {
    _restartIdle();
    final n = _ids.length;
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _tileKeys[i]?.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 150), alignment: 0.5);
        }
      });
    }
  }

  Future<void> _activate(int index) async {
    final id = _ids[index];
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
    return Row(
      children: [
        Icon(Icons.home_rounded, color: brandGreen, size: 32 * s),
        SizedBox(width: 12 * s),
        Text('Home Control', style: TextStyle(fontSize: 24 * s, fontWeight: FontWeight.w600)),
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
    if (_ids.isEmpty) {
      return _hint(s, Icons.playlist_add, 'Noch keine Entitäten ausgewählt.\nÖffne die App „Home Control“.');
    }
    final cols = widget.config.columns;
    return GridView.builder(
      padding: EdgeInsets.all(8 * s),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 14 * s,
        crossAxisSpacing: 14 * s,
        childAspectRatio: 1.55,
      ),
      itemCount: _ids.length,
      itemBuilder: (context, i) {
        final id = _ids[i];
        final key = _tileKeys.putIfAbsent(i, GlobalKey.new);
        return GestureDetector(
          key: key,
          onTap: () {
            setState(() => _selected = i);
            _restartIdle();
            _activate(i);
          },
          child: EntityTile(
            id: id,
            entity: widget.ha.states[id],
            selected: i == _selected,
            busy: _busy.contains(id),
            scale: s,
          ),
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
    return SizedBox(
      height: 22 * s,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _message != null
            ? Text(_message!, key: const ValueKey('msg'), style: style.copyWith(color: accentAmber), textAlign: TextAlign.center)
            : Text('◀ ▲ ▼ ▶  auswählen   ·   OK  schalten   ·   Zurück  schließen',
                key: const ValueKey('hint'), style: style, textAlign: TextAlign.center),
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
      ),
    );
  }
}
