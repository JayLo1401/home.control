import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/native_bridge.dart';

/// Tasten, die nicht als Ausloeser taugen (sonst ist die Navigation blockiert):
/// HOME, BACK, Steuerkreuz, OK, ENTER.
const _forbiddenKeys = {3, 4, 19, 20, 21, 22, 23, 66};

/// Wartet auf einen Tastendruck auf der Fernbedienung (ueber den Hintergrunddienst).
/// Gibt `null` zurueck bei Abbruch/Fehler; Meldungen werden als Snackbar gezeigt.
Future<TriggerKey?> learnKeyDialog(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  void snack(String t) => messenger.showSnackBar(SnackBar(content: Text(t)));

  if (!await NativeBridge.isServiceEnabled()) {
    snack('Zuerst den Hintergrunddienst in den Bedienungshilfen aktivieren.');
    return null;
  }
  if (!context.mounted) return null;
  final navigator = Navigator.of(context);

  var learned = false;
  final dialog = showDialog<void>(
    context: context,
    builder: (_) => const AlertDialog(
      icon: Icon(Icons.settings_remote, size: 48),
      title: Text('Taste drücken'),
      content: Text(
        'Drücke jetzt auf der Fernbedienung die Taste für dieses Panel.\n\n'
        'Kurz drücken öffnet das Panel, lang drücken löst die Lang-Drücken-Aktion aus. '
        'Die Taste verliert ihre normale Funktion.',
      ),
    ),
  );
  unawaited(dialog.then((_) {
    if (!learned) NativeBridge.cancelLearn();
  }));

  try {
    final key = await NativeBridge.learnKey().timeout(const Duration(seconds: 20));
    learned = true;
    navigator.pop();
    if (_forbiddenKeys.contains(key.code)) {
      snack('${key.name} kann nicht verwendet werden (wird zur Navigation gebraucht).');
      return null;
    }
    return key;
  } on TimeoutException {
    navigator.pop();
    snack('Keine Taste erkannt.');
  } on PlatformException catch (e) {
    navigator.pop();
    snack(e.message ?? 'Fehler');
  }
  return null;
}
