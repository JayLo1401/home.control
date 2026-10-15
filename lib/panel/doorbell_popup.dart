import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../ha/mobile_app.dart';

/// Tuerglocken-Meldung ueber allem: schwingende Glocke, Text, optional Kamerabild,
/// bleibt [DoorbellMessage.duration] bzw. die eingestellte Zeit stehen.
class DoorbellPopup extends StatefulWidget {
  final DoorbellMessage message;
  final AppConfig config;
  final VoidCallback onClose;

  const DoorbellPopup({super.key, required this.message, required this.config, required this.onClose});

  @override
  State<DoorbellPopup> createState() => _DoorbellPopupState();
}

class _DoorbellPopupState extends State<DoorbellPopup> with TickerProviderStateMixin {
  late final int _seconds = (widget.message.duration ?? widget.config.doorbell.durationSeconds).clamp(5, 600);
  late final _countdown = AnimationController(vsync: this, duration: Duration(seconds: _seconds))..forward();
  late final _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  late final DateTime _time = DateTime.now();
  Timer? _closeTimer;
  Timer? _cameraTimer;
  int _cameraTick = 0;

  @override
  void initState() {
    super.initState();
    _closeTimer = Timer(Duration(seconds: _seconds), widget.onClose);
    // Glocke schwingt nur waehrend der ersten Sekunden (wie der Gong).
    Timer(const Duration(seconds: 4), () {
      if (mounted) _shake.animateTo(0, duration: const Duration(milliseconds: 300));
    });
    if (widget.message.camera != null) {
      _cameraTimer = Timer.periodic(const Duration(seconds: 2), (_) => setState(() => _cameraTick++));
    }
  }

  @override
  void dispose() {
    _countdown.dispose();
    _shake.dispose();
    _closeTimer?.cancel();
    _cameraTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final size = MediaQuery.sizeOf(context);
    final s = (size.width / 1000).clamp(0.8, 1.8);
    final time = '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';
    final c = widget.config;

    return GestureDetector(
      onTap: widget.onClose,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: Container(
            width: min(size.width * 0.6, 760 * s),
            padding: EdgeInsets.all(28 * s),
            decoration: BoxDecoration(
              color: panelBackground.withValues(alpha: 0.97),
              borderRadius: BorderRadius.circular(24 * s),
              border: Border.all(color: accentAmber, width: 3),
              boxShadow: [BoxShadow(color: accentAmber.withValues(alpha: 0.35), blurRadius: 40, spreadRadius: 2)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  AnimatedBuilder(
                    animation: _shake,
                    builder: (_, child) => Transform.rotate(
                      angle: sin(_shake.value * 2 * pi * 3) * 0.35 * (1 - _shake.value * 0.3),
                      alignment: Alignment.topCenter,
                      child: child,
                    ),
                    child: Icon(Icons.notifications_active, size: 72 * s, color: accentAmber),
                  ),
                  SizedBox(width: 22 * s),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(m.title,
                          style: TextStyle(fontSize: 34 * s, fontWeight: FontWeight.w700, color: Colors.white)),
                      if (m.message.isNotEmpty) ...[
                        SizedBox(height: 4 * s),
                        Text(m.message, style: TextStyle(fontSize: 22 * s, color: Colors.white70)),
                      ],
                    ]),
                  ),
                  Text(time, style: TextStyle(fontSize: 22 * s, color: Colors.white54)),
                ]),
                if (m.camera != null) ...[
                  SizedBox(height: 20 * s),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14 * s),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.network(
                        '${c.haUrl}/api/camera_proxy/${m.camera}?t=$_cameraTick',
                        headers: {'Authorization': 'Bearer ${c.token}'},
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: tileBackground,
                          child: Center(child: Icon(Icons.videocam_off, size: 48 * s, color: Colors.white24)),
                        ),
                      ),
                    ),
                  ),
                ],
                SizedBox(height: 22 * s),
                AnimatedBuilder(
                  animation: _countdown,
                  builder: (_, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: 1 - _countdown.value,
                      minHeight: 6 * s,
                      color: accentAmber,
                      backgroundColor: Colors.white10,
                    ),
                  ),
                ),
                SizedBox(height: 10 * s),
                Text('OK oder Zurück schließt die Meldung',
                    style: TextStyle(fontSize: 14 * s, color: Colors.white38)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
