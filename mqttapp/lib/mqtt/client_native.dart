import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'settings.dart';

MqttClient createMqttClient(BrokerSettings settings, String clientId) {
  return MqttServerClient.withPort(
    settings.host,
    clientId,
    settings.port,
    maxConnectionAttempts: 1,
  )..connectionTimeout = 8000;
}
