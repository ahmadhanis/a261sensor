import 'package:flutter_test/flutter_test.dart';
import 'package:mqttapp/mqtt/sensor_reading.dart';
import 'package:mqttapp/mqtt/settings.dart';

void main() {
  test('parses the ESP32 payload and retained flag', () {
    final reading = SensorReading.parse(
      BrokerSettings.samplePayload,
      retained: true,
    )!;
    expect(reading.device, 'esp32_ahmadhanis');
    expect(reading.temperature, 25.8);
    expect(reading.humidity, 61.6);
    expect(reading.relay, 'OFF');
    expect(reading.retained, isTrue);
  });

  test('accepts temperature alias without inventing other measurements', () {
    final reading = SensorReading.parse('{"temp":25}')!;
    expect(reading.temperature, 25);
    expect(reading.humidity, isNull);
    expect(reading.relay, isNull);
  });

  test('ignores malformed, unrelated, and non-finite sensor data', () {
    for (final payload in [
      '{temp:25}',
      'hello',
      '[]',
      'null',
      '{}',
      '{"temp":"NaN"}',
      '{"relay":"unknown"}',
    ]) {
      expect(SensorReading.parse(payload), isNull, reason: payload);
    }
    expect(
      SensorReading.parse('{"temperature_c":"26.2","relay":"on"}')!.relay,
      'ON',
    );
  });

  test('publishing stays within the assigned namespace without wildcards', () {
    expect(
      BrokerSettings.validatePublishTopic(BrokerSettings.sensorTopic),
      isNull,
    );
    for (final topic in [
      'other/sensor',
      'students/ahmadhanis/',
      'students/ahmadhanis/#',
      'students/ahmadhanis/+',
      'students/ahmadhanis/sensor\u0000',
    ]) {
      expect(
        BrokerSettings.validatePublishTopic(topic),
        isNotNull,
        reason: topic,
      );
    }
  });
}
