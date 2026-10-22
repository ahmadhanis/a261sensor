#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>

const char* WIFI_SSID = "myUUM_Guest";
const char* WIFI_PASSWORD = "";
const char* API_URL = "http://slum78.myddns.me/iot/relay/api.php";
const char* API_KEY = "ebd499c020fcaee25e145707e6889b2847dba5e9ab4b863bc9579688eef3c8a5";
const char* DEVICE_ID = "esp32-01";
const int RELAY_PIN = 4;
const bool ACTIVE_LOW = true; // Match your relay module.
bool relayOn = false;
unsigned long lastPoll = 0;
void applyRelay(bool on) {
  digitalWrite(RELAY_PIN, (on != ACTIVE_LOW) ? HIGH : LOW);
  relayOn = on;
}
void setup() {
  Serial.begin(115200);
  digitalWrite(RELAY_PIN, ACTIVE_LOW ? HIGH : LOW);
  pinMode(RELAY_PIN, OUTPUT);
  applyRelay(false);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  WiFi.setAutoReconnect(true);
}
void loop() {
  if (WiFi.status() != WL_CONNECTED || millis() - lastPoll < 2000) return;
  lastPoll = millis();
  HTTPClient http;
  http.setTimeout(5000);
  http.begin(API_URL);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("X-API-Key", API_KEY);
  JsonDocument report;
  report["device_id"] = DEVICE_ID;
  report["relay_status"] = relayOn ? 1 : 0;
  String body;
  serializeJson(report, body);
  int code = http.POST(body);
  if (code == 200) {
    JsonDocument response;
    if (!deserializeJson(response, http.getString()) && response["desired_status"].is<int>()) {
      int desired = response["desired_status"].as<int>();
      if (desired == 0 || desired == 1) applyRelay(desired == 1);
    }
  } else {
    Serial.printf("Relay API error: %d\n", code);
  }
  http.end();
}
