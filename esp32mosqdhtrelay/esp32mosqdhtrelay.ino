#include <WiFi.h>
#include <PubSubClient.h>
#include <DHT.h>
#include <ArduinoJson.h>

// ---------------- Pin & Sensor Configuration ----------------
#define DHTPIN 4          // D4 (GPIO 4)
#define DHTTYPE DHT11     // DHT11 sensor
#define RELAY_PIN 18      // D18 (GPIO 18)

// Set to true if your relay turns ON with LOW (active-low module),
// or false if it turns ON with HIGH (active-high module).
const bool RELAY_ACTIVE_LOW = false;

// ---------------- Wi-Fi & MQTT Configuration ----------------
const char* WIFI_SSID = "myUUM_Guest";
const char* WIFI_PASSWORD = ""; // Open network (no password)

const char* MQTT_SERVER = "10.19.5.233";
const int MQTT_PORT = 1884;
const char* MQTT_USER = "ahmadhanis";
const char* MQTT_PASS = "abc123";
const char* MQTT_TOPIC = "students/ahmadhanis/sensor";

// Publish interval (in milliseconds)
const unsigned long PUBLISH_INTERVAL_MS = 5000;

// ---------------- Global Objects & State ----------------
WiFiClient espClient;
PubSubClient mqttClient(espClient);
DHT dht(DHTPIN, DHTTYPE);

unsigned long lastPublishMs = 0;
bool relayState = false; // false = OFF, true = ON

void setRelay(bool turnOn) {
  relayState = turnOn;
  if (RELAY_ACTIVE_LOW) {
    digitalWrite(RELAY_PIN, turnOn ? LOW : HIGH);
  } else {
    digitalWrite(RELAY_PIN, turnOn ? HIGH : LOW);
  }
}

void connectWiFi() {
  if (WiFi.status() == WL_CONNECTED) return;

  Serial.print("Connecting to Wi-Fi: ");
  Serial.println(WIFI_SSID);

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID); // Open Wi-Fi (no password)

  unsigned long startAttempt = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - startAttempt < 20000) {
    delay(500);
    Serial.print(".");
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nWi-Fi connected!");
    Serial.print("IP Address: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("\nWi-Fi connection timed out. Will retry...");
  }
}

void connectMQTT() {
  if (WiFi.status() != WL_CONNECTED) {
    connectWiFi();
    if (WiFi.status() != WL_CONNECTED) return;
  }

  mqttClient.setServer(MQTT_SERVER, MQTT_PORT);

  while (!mqttClient.connected() && WiFi.status() == WL_CONNECTED) {
    String clientId = "ESP32_ahmadhanis_" + String((uint32_t)ESP.getEfuseMac(), HEX);
    Serial.print("Connecting to MQTT broker ");
    Serial.print(MQTT_SERVER);
    Serial.print(":");
    Serial.print(MQTT_PORT);
    Serial.print(" ... ");

    if (mqttClient.connect(clientId.c_str(), MQTT_USER, MQTT_PASS)) {
      Serial.println("connected!");
    } else {
      Serial.print("failed (rc=");
      Serial.print(mqttClient.state());
      Serial.println("). Retrying in 3 seconds...");
      delay(3000);
    }
  }
}

void publishSensorData() {
  float humidity = dht.readHumidity();
  float temperature = dht.readTemperature(); // Celsius

  if (isnan(humidity) || isnan(temperature)) {
    Serial.println("Failed to read from DHT11 sensor!");
    return;
  }

  // Example relay logic: turn ON relay if temperature >= 30.0 C (adjust to your need)
  if (temperature >= 30.0) {
    setRelay(true);
  } else {
    setRelay(false);
  }

  // Build JSON payload matching your topic/broker setup
  JsonDocument doc;
  doc["device"] = "esp32_ahmadhanis";
  doc["temperature_c"] = round(temperature * 10) / 10.0;
  doc["humidity_pct"] = round(humidity * 10) / 10.0;
  doc["relay"] = relayState ? "ON" : "OFF";

  char payload[256];
  size_t len = serializeJson(doc, payload, sizeof(payload));

  if (len > 0 && mqttClient.publish(MQTT_TOPIC, payload)) {
    Serial.print("Published to [");
    Serial.print(MQTT_TOPIC);
    Serial.print("]: ");
    Serial.println(payload);
  } else {
    Serial.println("MQTT publish failed!");
  }
}

void setup() {
  Serial.begin(115200);
  delay(500);

  pinMode(RELAY_PIN, OUTPUT);
  setRelay(false); // Start with relay OFF

  dht.begin();
  connectWiFi();
  connectMQTT();
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    connectWiFi();
  }

  if (!mqttClient.connected()) {
    connectMQTT();
  }
  mqttClient.loop();

  unsigned long now = millis();
  if (now - lastPublishMs >= PUBLISH_INTERVAL_MS) {
    lastPublishMs = now;
    publishSensorData();
  }
}