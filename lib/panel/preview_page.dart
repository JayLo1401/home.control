import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config.dart';
import '../ha/ha_client.dart';
import 'quick_panel.dart';

/// Panel in der App – zum Testen auf Tablet (Touch) oder TV ohne Dienst.
class PreviewPage extends StatelessWidget {
  final HaClient ha;
  final AppConfig config;
  final PanelConfig panel;
  PreviewPage({super.key, required this.ha, required this.config, required this.panel});

  final _panel = GlobalKey<QuickPanelState>();

  static final _keys = {
    LogicalKeyboardKey.arrowUp: PanelKey.up,
    LogicalKeyboardKey.arrowDown: PanelKey.down,
    LogicalKeyboardKey.arrowLeft: PanelKey.left,
    LogicalKeyboardKey.arrowRight: PanelKey.right,
    LogicalKeyboardKey.select: PanelKey.select,
    LogicalKeyboardKey.enter: PanelKey.select,
    LogicalKeyboardKey.numpadEnter: PanelKey.select,
    LogicalKeyboardKey.gameButtonA: PanelKey.select,
    LogicalKeyboardKey.space: PanelKey.select,
  };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      // Zurueck verlaesst erst die Gruppe, dann die Vorschau.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !(_panel.currentState?.handleBack() ?? false)) Navigator.of(context).pop();
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyUpEvent) return KeyEventResult.ignored;
          final k = _keys[event.logicalKey];
          if (k == null) return KeyEventResult.ignored;
          _panel.currentState?.handleKey(k);
          return KeyEventResult.handled;
        },
        child: Material(
          type: MaterialType.transparency,
          child: QuickPanel(
            key: _panel,
            ha: ha,
            config: config,
            panel: panel,
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}
