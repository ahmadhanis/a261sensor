import 'dart:convert';

class SensorReading {
  const SensorReading({
    this.device,
    this.temperature,
    this.humidity,
    this.relay,
    required this.receivedAt,
    this.retained = false,
  });

  final String? device;
  final double? temperature;
  final double? humidity;
  final String? relay;
  final DateTime receivedAt;
  final bool retained;

  static SensorReading? parse(
    String payload, {
    DateTime? receivedAt,
    bool retained = false,
  }) {
    try {
      final data = jsonDecode(payload);
      if (data is! Map<String, dynamic>) return null;
      double? number(dynamic value) {
        final parsed = value is num
            ? value.toDouble()
            : double.tryParse(value.toString());
        return parsed != null && parsed.isFinite ? parsed : null;
      }

      final temperature = number(data['temperature_c'] ?? data['temp']);
      final humidity = number(data['humidity_pct']);
      final rawRelay = data['relay']?.toString().toUpperCase();
      final relay = ['ON', 'OFF'].contains(rawRelay) ? rawRelay : null;
      if (temperature == null && humidity == null && relay == null) return null;
      return SensorReading(
        device: data['device'] is String ? data['device'] as String : null,
        temperature: temperature,
        humidity: humidity,
        relay: relay,
        receivedAt: receivedAt ?? DateTime.now(),
        retained: retained,
      );
    } on FormatException {
      return null;
    }
  }
}
