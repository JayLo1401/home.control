import 'package:flutter/material.dart';

class HaEntity {
  final String entityId;
  final String state;
  final Map<String, dynamic> attributes;

  const HaEntity(this.entityId, this.state, this.attributes);

  factory HaEntity.fromJson(Map<String, dynamic> j) => HaEntity(
        j['entity_id'] as String,
        '${j['state']}',
        (j['attributes'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  String get domain => entityId.split('.').first;
  String get name => (attributes['friendly_name'] as String?) ?? entityId;
  String? get unit => attributes['unit_of_measurement'] as String?;
  String? get deviceClass => attributes['device_class'] as String?;
  bool get isUnavailable => state == 'unavailable' || state == 'unknown';
}

/// Ein auszufuehrender HA-Service.
class HaAction {
  final String domain;
  final String service;
  const HaAction(this.domain, this.service);
}

const _toggleDomains = {
  'light', 'switch', 'fan', 'input_boolean', 'automation', 'siren', 'humidifier',
  'cover', 'media_player', 'climate', 'remote', 'water_heater',
};

/// Was passiert bei OK auf dieser Entitaet? `null` = reine Statusanzeige.
HaAction? primaryAction(HaEntity e) {
  if (e.isUnavailable && e.domain != 'scene' && e.domain != 'script') return null;
  final d = e.domain;
  if (_toggleDomains.contains(d)) return HaAction(d, 'toggle');
  switch (d) {
    case 'scene':
    case 'script':
      return HaAction(d, 'turn_on');
    case 'button':
    case 'input_button':
      return HaAction(d, 'press');
    case 'lock':
      return HaAction(d, e.state == 'locked' ? 'unlock' : 'lock');
    case 'vacuum':
      return HaAction(d, e.state == 'cleaning' ? 'return_to_base' : 'start');
  }
  return null;
}

/// Service fuer die Lang-Druecken-Aktion. [mode]: 'toggle', 'on', 'off'.
HaAction? longPressServiceFor(HaEntity e, String mode) {
  if (mode == 'toggle') return primaryAction(e);
  return switch (e.domain) {
    'scene' || 'script' => HaAction(e.domain, 'turn_on'),
    'button' || 'input_button' => HaAction(e.domain, 'press'),
    'lock' => HaAction('lock', mode == 'on' ? 'unlock' : 'lock'),
    'cover' => HaAction('cover', mode == 'on' ? 'open_cover' : 'close_cover'),
    _ => HaAction(e.domain, mode == 'on' ? 'turn_on' : 'turn_off'),
  };
}

/// "eingeschaltet", "ausgeschaltet", "ausgefuehrt" … fuer das Halte-Popup.
String longPressVerb(HaEntity e, String mode) {
  final on = switch (mode) {
    'on' => true,
    'off' => false,
    _ => !isActive(e),
  };
  return switch (e.domain) {
    'scene' || 'script' || 'button' || 'input_button' => 'ausgeführt',
    'lock' => on ? 'entriegelt' : 'verriegelt',
    'cover' => on ? 'geöffnet' : 'geschlossen',
    _ => on ? 'eingeschaltet' : 'ausgeschaltet',
  };
}

bool isSensor(HaEntity e) => e.domain == 'sensor' || e.domain == 'weather';

/// Aktiv = "an"/offen/laeuft – wird farbig hervorgehoben.
bool isActive(HaEntity e) {
  switch (e.domain) {
    case 'lock':
      return e.state == 'unlocked';
    case 'cover':
      return e.state == 'open' || e.state == 'opening';
    case 'media_player':
      return e.state == 'playing';
    case 'climate':
      return e.state != 'off' && !e.isUnavailable;
    case 'vacuum':
      return e.state == 'cleaning';
    case 'sensor':
    case 'scene':
    case 'script':
    case 'button':
    case 'input_button':
      return false;
  }
  return e.state == 'on' || e.state == 'home' || e.state == 'open';
}

const _stateLabels = {
  'on': 'An',
  'off': 'Aus',
  'open': 'Offen',
  'opening': 'Öffnet…',
  'closed': 'Geschlossen',
  'closing': 'Schließt…',
  'locked': 'Verriegelt',
  'unlocked': 'Entriegelt',
  'locking': 'Verriegelt…',
  'unlocking': 'Entriegelt…',
  'playing': 'Spielt',
  'paused': 'Pausiert',
  'idle': 'Bereit',
  'standby': 'Standby',
  'home': 'Zuhause',
  'not_home': 'Abwesend',
  'cleaning': 'Saugt',
  'docked': 'Angedockt',
  'returning': 'Kehrt zurück',
  'heat': 'Heizen',
  'cool': 'Kühlen',
  'auto': 'Automatik',
  'heat_cool': 'Heizen/Kühlen',
  'unavailable': 'Nicht verfügbar',
  'unknown': 'Unbekannt',
};

String stateLabel(HaEntity e) {
  if (e.domain == 'scene' || e.domain == 'script') return 'Ausführen';
  if (e.domain == 'button' || e.domain == 'input_button') return 'Drücken';
  if (e.domain == 'binary_sensor' && !e.isUnavailable) {
    final on = e.state == 'on';
    switch (e.deviceClass) {
      case 'door':
      case 'window':
      case 'garage_door':
      case 'opening':
        return on ? 'Offen' : 'Geschlossen';
      case 'motion':
      case 'occupancy':
      case 'presence':
        return on ? 'Erkannt' : 'Frei';
      case 'moisture':
        return on ? 'Nass' : 'Trocken';
    }
  }
  if (e.domain == 'climate' && !e.isUnavailable) {
    final cur = e.attributes['current_temperature'];
    final target = e.attributes['temperature'];
    final mode = _stateLabels[e.state] ?? e.state;
    if (cur != null) return '$cur° → ${target ?? '–'}° · $mode';
    return mode;
  }
  if (e.domain == 'light' && e.state == 'on') {
    final b = e.attributes['brightness'];
    if (b is num) return 'An · ${(b / 255 * 100).round()} %';
  }
  if (e.domain == 'cover' && e.attributes['current_position'] is num && e.state == 'open') {
    return 'Offen · ${e.attributes['current_position']} %';
  }
  final label = _stateLabels[e.state];
  if (label != null) return label;
  final unit = e.unit;
  return unit == null ? e.state : '${e.state} $unit';
}

IconData iconFor(HaEntity e) {
  final on = isActive(e);
  switch (e.domain) {
    case 'light':
      return on ? Icons.lightbulb : Icons.lightbulb_outline;
    case 'switch':
    case 'input_boolean':
      return on ? Icons.toggle_on : Icons.toggle_off;
    case 'fan':
      return on ? Icons.air : Icons.mode_fan_off;
    case 'cover':
      return on ? Icons.blinds : Icons.blinds_closed;
    case 'lock':
      return on ? Icons.lock_open : Icons.lock;
    case 'media_player':
      return on ? Icons.play_circle : Icons.speaker;
    case 'climate':
    case 'water_heater':
      return Icons.thermostat;
    case 'scene':
      return Icons.palette;
    case 'script':
      return Icons.play_arrow;
    case 'automation':
      return Icons.smart_toy;
    case 'button':
    case 'input_button':
      return Icons.radio_button_checked;
    case 'vacuum':
      return Icons.cleaning_services;
    case 'person':
    case 'device_tracker':
      return on ? Icons.home : Icons.directions_walk;
    case 'siren':
      return Icons.campaign;
    case 'camera':
      return Icons.videocam;
    case 'weather':
      return Icons.cloud;
    case 'sun':
      return e.state == 'above_horizon' ? Icons.wb_sunny : Icons.nightlight;
    case 'binary_sensor':
      switch (e.deviceClass) {
        case 'door':
        case 'garage_door':
        case 'opening':
          return on ? Icons.door_front_door : Icons.door_front_door_outlined;
        case 'window':
          return on ? Icons.window : Icons.window_outlined;
        case 'motion':
        case 'occupancy':
        case 'presence':
          return on ? Icons.directions_run : Icons.accessibility_new;
        case 'moisture':
          return Icons.water_drop;
        case 'smoke':
          return Icons.local_fire_department;
      }
      return on ? Icons.radio_button_checked : Icons.radio_button_unchecked;
    case 'sensor':
      switch (e.deviceClass) {
        case 'temperature':
          return Icons.device_thermostat;
        case 'humidity':
          return Icons.water_drop_outlined;
        case 'power':
        case 'energy':
          return Icons.bolt;
        case 'battery':
          return Icons.battery_std;
        case 'illuminance':
          return Icons.light_mode;
      }
      return Icons.sensors;
  }
  return Icons.circle_outlined;
}
