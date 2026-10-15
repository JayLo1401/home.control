import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config.dart';
import 'ha_entity.dart';

/// Material Design Icons (gleiche Symbole wie in Home Assistant, @mdi 7.4.47).
/// Font + Namensliste liegen unter assets/mdi/ und werden beim Start geladen.
class Mdi {
  static const fontFamily = 'MaterialDesignIcons';
  static Map<String, IconData> _byName = const {};

  /// Alle Symbole nach HA-Namen ("hot-tub").
  static Map<String, IconData> get icons => _byName;

  static Future<void> load() async {
    if (_byName.isNotEmpty) return;
    final text = await rootBundle.loadString('assets/mdi/names.txt');
    _byName = {
      for (final line in text.split('\n'))
        if (line.split(' ') case [final name, final hex])
          // Dynamische Symbole -> Release-Build braucht --no-tree-shake-icons (siehe deploy.ps1).
          // ignore: non_const_argument_for_const_parameter
          name: IconData(int.parse(hex, radix: 16), fontFamily: fontFamily),
    };
  }
}

/// "mdi:hot-tub" -> IconData (oder null).
IconData? mdiIcon(String? ref) {
  if (ref == null || !ref.startsWith('mdi:')) return null;
  return Mdi.icons[ref.substring(4)];
}

/// Anzeigename: eigener Name -> Name aus HA -> Entitaets-ID.
String entityName(AppConfig config, String id, HaEntity? e) {
  final custom = config.overrides[id]?.name;
  if (custom != null && custom.isNotEmpty) return custom;
  return e?.name ?? id;
}

/// Symbol: eigenes -> in HA gesetztes -> Standard je Typ/Zustand.
IconData entityIcon(AppConfig config, String id, HaEntity? e) =>
    mdiIcon(config.overrides[id]?.icon) ??
    mdiIcon(e?.attributes['icon'] as String?) ??
    (e == null ? Icons.help_outline : iconFor(e));
