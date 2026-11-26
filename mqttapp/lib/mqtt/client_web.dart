import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

import 'settings.dart';

MqttClient createMqttClient(BrokerSettings settings, String clientId) {
  final uri = Uri.parse(settings.webSocketUrl);
  return MqttBrowserClient(
      settings.webSocketUrl,
      clientId,
      maxConnectionAttempts: 1,
    )
    ..port = uri.hasPort ? uri.port : (uri.scheme == 'wss' ? 443 : 80)
    ..websocketProtocols = MqttClientConstants.protocolsSingleDefault;
}
