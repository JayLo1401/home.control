import 'dart:async';

import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../ha/entity_look.dart';
import '../ha/ha_client.dart';
import '../ha/ha_entity.dart';

enum _HoldState { holding, running, done, cancelled, failed }

/// "Gedrückt halten, bis X ausgeschaltet wird" mit Fortschrittsring.
/// Laeuft der Ring durch, wird die Aktion ausgefuehrt; [release] vorher = abgebrochen.
class HoldPopup extends StatefulWidget {
  final HaClient ha;
  final AppConfig config;
  final LongPressAction action;
  final VoidCallback onClose;

  /// Taste wurde schon losgelassen, bevor das Popup aufgebaut war.
  final bool releasedBeforeStart;

  const HoldPopup({
    super.key,
    required this.ha,
    required this.config,
    required this.action,
    required this.onClose,
    this.releasedBeforeStart = false,
  });

  @override
  State<HoldPopup> createState() => HoldPopupState();
}

class HoldPopupState extends State<HoldPopup> with SingleTickerProviderStateMixin {
  late final AnimationController _progress;
  _HoldState _state = _HoldState.holding;
  String? _error;
  Timer? _closeTimer;

  /// Zum Start festgehalten, damit sich der Text waehrend des Haltens nicht aendert.
  late final HaEntity? _entity = widget.ha.states[widget.action.entityId];
  late final String _verb = _entity == null ? 'geschaltet' : longPressVerb(_entity, widget.action.mode);

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this, duration: Duration(milliseconds: widget.action.holdMs))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _execute();
      });
    if (widget.releasedBeforeStart) {
      _state = _HoldState.cancelled;
      _closeAfter(const Duration(milliseconds: 1200));
    } else {
      _progress.forward();
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _closeTimer?.cancel();
    super.dispose();
  }

  /// Taste losgelassen.
  void release() {
    if (_state != _HoldState.holding) return;
    _progress.stop();
    setState(() => _state = _HoldState.cancelled);
    _closeAfter(const Duration(milliseconds: 1200));
  }

  Future<void> _execute() async {
    setState(() => _state = _HoldState.running);
    try {
      final e = _entity;
      if (e == null) throw HaException('Entität ${widget.action.entityId} nicht gefunden');
      final a = longPressServiceFor(e, widget.action.mode);
      if (a == null) throw HaException('${entityName(widget.config, e.entityId, e)} ist nicht schaltbar');
      await widget.ha.callService(a.domain, a.service, entityId: e.entityId);
      if (mounted) setState(() => _state = _HoldState.done);
    } catch (err) {
      if (mounted) {
        setState(() {
          _state = _HoldState.failed;
          _error = '$err';
        });
      }
    }
    _closeAfter(const Duration(milliseconds: 1800));
  }

  void _closeAfter(Duration d) {
    _closeTimer?.cancel();
    _closeTimer = Timer(d, widget.onClose);
  }

  @override
  Widget build(BuildContext context) {
    final name = entityName(widget.config, widget.action.entityId, _entity);
    final (color, icon, title) = switch (_state) {
      _HoldState.holding => (brandGreen, Icons.touch_app, 'Gedrückt halten …'),
      _HoldState.running => (brandGreen, Icons.sync, 'Wird ausgeführt …'),
      _HoldState.done => (brandGreen, Icons.check_circle, '$name $_verb'),
      _HoldState.cancelled => (Colors.white54, Icons.cancel, 'Abgebrochen'),
      _HoldState.failed => (Colors.redAccent, Icons.error, 'Fehler'),
    };
    final subtitle = switch (_state) {
      _HoldState.holding || _HoldState.running => 'bis „$name“ $_verb wird',
      _HoldState.done => '',
      _HoldState.cancelled => '„$name“ wurde nicht geschaltet',
      _HoldState.failed => _error ?? '',
    };

    return Center(
      child: LayoutBuilder(builder: (context, c) {
        final s = (MediaQuery.sizeOf(context).width / 1000).clamp(0.8, 1.8);
        return Container(
          width: 460 * s,
          padding: EdgeInsets.all(28 * s),
          decoration: BoxDecoration(
            color: panelBackground.withValues(alpha: 0.97),
            borderRadius: BorderRadius.circular(24 * s),
            border: Border.all(color: color, width: 3),
            boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 40)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 110 * s,
                height: 110 * s,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _progress,
                      builder: (_, _) => SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: _state == _HoldState.running ? null : _progress.value,
                          strokeWidth: 8 * s,
                          color: color,
                          backgroundColor: Colors.white12,
                        ),
                      ),
                    ),
                    Icon(icon, size: 48 * s, color: color),
                  ],
                ),
              ),
              SizedBox(height: 22 * s),
              Text(title,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24 * s, fontWeight: FontWeight.w600, color: Colors.white)),
              if (subtitle.isNotEmpty) ...[
                SizedBox(height: 8 * s),
                Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 17 * s, color: Colors.white70)),
              ],
            ],
          ),
        );
      }),
    );
  }
}
