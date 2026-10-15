import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Eintrag in einem Panel: einzelne Entitaet oder Gruppe.
sealed class PanelItem {
  Map<String, dynamic> toJson();

  static PanelItem fromJson(Map<String, dynamic> j) => j.containsKey('group')
      ? GroupItem(j['group'] as String, [...?(j['entities'] as List?)?.cast<String>()])
      : EntityItem(j['entity'] as String);
}

class EntityItem extends PanelItem {
  String entityId;
  EntityItem(this.entityId);

  @override
  Map<String, dynamic> toJson() => {'entity': entityId};
}

/// Gruppe (z. B. "Whirlpool"): Sensorwerte werden auf der Kachel angezeigt,
/// OK oeffnet die Gruppe.
class GroupItem extends PanelItem {
  String name;
  List<String> entities;
  GroupItem(this.name, [List<String>? entities]) : entities = entities ?? [];

  @override
  Map<String, dynamic> toJson() => {'group': name, 'entities': entities};
}

/// Aktion beim langen Druecken der Panel-Taste.
class LongPressAction {
  String entityId;

  /// 'toggle', 'on' oder 'off'
  String mode;
  int holdMs;

  LongPressAction(this.entityId, {this.mode = 'toggle', this.holdMs = 2000});

  Map<String, dynamic> toJson() => {'entity': entityId, 'mode': mode, 'holdMs': holdMs};

  factory LongPressAction.fromJson(Map<String, dynamic> j) => LongPressAction(
        j['entity'] as String,
        mode: j['mode'] as String? ?? 'toggle',
        holdMs: j['holdMs'] as int? ?? 2000,
      );
}

class PanelConfig {
  String name;
  int keyCode;
  String keyName;
  List<PanelItem> items;
  LongPressAction? longPress;

  PanelConfig(this.name, {this.keyCode = 0, this.keyName = '', List<PanelItem>? items, this.longPress})
      : items = items ?? [];

  /// Alle Entitaeten des Panels inkl. Gruppeninhalt.
  Iterable<String> get allEntities sync* {
    for (final i in items) {
      switch (i) {
        case EntityItem(:final entityId):
          yield entityId;
        case GroupItem(:final entities):
          yield* entities;
      }
    }
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'keyCode': keyCode,
        'keyName': keyName,
        'items': [for (final i in items) i.toJson()],
        if (longPress != null) 'longPress': longPress!.toJson(),
      };

  factory PanelConfig.fromJson(Map<String, dynamic> j) => PanelConfig(
        j['name'] as String? ?? 'Panel',
        keyCode: j['keyCode'] as int? ?? 0,
        keyName: j['keyName'] as String? ?? '',
        items: [
          for (final i in (j['items'] as List? ?? const [])) PanelItem.fromJson((i as Map).cast<String, dynamic>()),
        ],
        longPress: j['longPress'] == null
            ? null
            : LongPressAction.fromJson((j['longPress'] as Map).cast<String, dynamic>()),
      );
}

/// App-Konfiguration. Wird von App und Overlay-Engine gemeinsam genutzt
/// (beide laufen im selben Prozess, deshalb vor jedem Lesen `reload()`).
class AppConfig {
  String haUrl;
  String token;
  bool allowBadCertificates;
  List<PanelConfig> panels;
  int columns;
  int panelPercent;
  int autoCloseSeconds;

  AppConfig({
    this.haUrl = '',
    this.token = '',
    this.allowBadCertificates = false,
    List<PanelConfig>? panels,
    this.columns = 4,
    this.panelPercent = 80,
    this.autoCloseSeconds = 30,
  }) : panels = panels ?? [];

  bool get isConfigured => haUrl.isNotEmpty && token.isNotEmpty;

  PanelConfig? panelForKey(int keyCode) {
    for (final p in panels) {
      if (p.keyCode == keyCode) return p;
    }
    return null;
  }

  static Future<AppConfig> load() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    var panels = <PanelConfig>[];
    final json = p.getString('panels');
    if (json != null) {
      panels = [for (final j in jsonDecode(json) as List) PanelConfig.fromJson((j as Map).cast<String, dynamic>())];
    } else {
      // Migration aus Version 0.1 (eine flache Entitaetenliste)
      final old = p.getStringList('entities');
      if (old != null && old.isNotEmpty) {
        panels = [PanelConfig('Panel 1', items: [for (final e in old) EntityItem(e)])];
      }
    }
    return AppConfig(
      haUrl: p.getString('ha_url') ?? '',
      token: p.getString('ha_token') ?? '',
      allowBadCertificates: p.getBool('ha_insecure') ?? false,
      panels: panels,
      columns: p.getInt('columns') ?? 4,
      panelPercent: p.getInt('panel_percent') ?? 80,
      autoCloseSeconds: p.getInt('auto_close') ?? 30,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('ha_url', haUrl);
    await p.setString('ha_token', token);
    await p.setBool('ha_insecure', allowBadCertificates);
    await p.setString('panels', jsonEncode([for (final x in panels) x.toJson()]));
    await p.remove('entities');
    await p.setInt('columns', columns);
    await p.setInt('panel_percent', panelPercent);
    await p.setInt('auto_close', autoCloseSeconds);
  }

  // ------------------------------------------------------------ Textformat (Browser)
  //
  //   == Wohnzimmer
  //   light.wohnzimmer
  //   -- Whirlpool
  //   switch.whirlpool_pumpe
  //   sensor.whirlpool_temperatur
  //   --
  //   scene.kino
  //
  // "== Name" beginnt ein Panel, "-- Name" eine Gruppe, "--" allein beendet die Gruppe.
  // Taste und Lang-Druecken-Aktion werden ueber den Panelnamen beibehalten.

  String panelsToText() {
    final b = StringBuffer();
    for (final p in panels) {
      b.writeln('== ${p.name}');
      for (final i in p.items) {
        switch (i) {
          case EntityItem(:final entityId):
            b.writeln(entityId);
          case GroupItem(:final name, :final entities):
            b.writeln('-- $name');
            entities.forEach(b.writeln);
            b.writeln('--');
        }
      }
      b.writeln();
    }
    return b.toString().trim();
  }

  void panelsFromText(String text) {
    final old = {for (final p in panels) p.name: p};
    final result = <PanelConfig>[];
    PanelConfig? panel;
    GroupItem? group;
    for (var line in const LineSplitter().convert(text)) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('==')) {
        final name = line.substring(2).trim();
        final prev = old[name];
        panel = PanelConfig(name.isEmpty ? 'Panel ${result.length + 1}' : name,
            keyCode: prev?.keyCode ?? 0, keyName: prev?.keyName ?? '', longPress: prev?.longPress);
        result.add(panel);
        group = null;
      } else if (line.startsWith('--')) {
        final name = line.substring(2).trim();
        group = null;
        if (name.isNotEmpty) {
          panel ??= _addDefaultPanel(result);
          group = GroupItem(name);
          panel.items.add(group);
        }
      } else if (line.contains('.')) {
        final id = line.split(RegExp(r'\s')).first;
        if (group != null) {
          group.entities.add(id);
        } else {
          (panel ??= _addDefaultPanel(result)).items.add(EntityItem(id));
        }
      }
    }
    panels = result;
  }

  static PanelConfig _addDefaultPanel(List<PanelConfig> list) {
    final p = PanelConfig('Panel ${list.length + 1}');
    list.add(p);
    return p;
  }
}
