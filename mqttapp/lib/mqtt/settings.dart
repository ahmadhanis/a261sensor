class BrokerSettings {
  const BrokerSettings({
    this.host = '10.19.5.233',
    this.port = 1884,
    this.webSocketUrl = 'ws://10.19.5.233:9001',
    this.username = 'ahmadhanis',
    this.password = const String.fromEnvironment(
      'MQTT_PASSWORD',
      defaultValue: 'abc123',
    ),
  });

  static const topicPrefix = 'students/ahmadhanis/';
  static const subscription = '$topicPrefix#';
  static const sensorTopic = '${topicPrefix}sensor';
  static const samplePayload =
      '{"device":"esp32_ahmadhanis","temperature_c":25.8,'
      '"humidity_pct":61.6,"relay":"OFF"}';

  final String host;
  final int port;
  final String webSocketUrl;
  final String username;
  final String password;

  static String? validatePublishTopic(String topic) {
    if (!topic.startsWith(topicPrefix) || topic.length <= topicPrefix.length) {
      return 'Use a topic inside $topicPrefix';
    }
    if (topic.contains(RegExp(r'[+#\x00]'))) {
      return 'Publish topics cannot contain wildcards or null characters.';
    }
    return null;
  }
}
