#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <DHT.h>
#include <time.h>
#include <sys/time.h>
#include "firebase_ca.h"

// Your settings
const char* WIFI_SSID = "myUUM_Guest";
const char* FIREBASE_URL = "https://iotprojects-62001-default-rtdb.asia-southeast1.firebasedatabase.app";
const char* DEVICE_ID = "esp32-01"; // Use a different ID for each ESP32.
const int DHT_PIN = 4;       // D4
const int RELAY_PIN = 18;    // D18
const bool RELAY_ACTIVE_LOW = false; // Set true if your relay turns ON with LOW.

DHT dht(DHT_PIN, DHT11);
bool relayOn = false;
unsigned long lastSensor = 0;
unsigned long lastRelay = 0;
unsigned long lastWiFiAttempt = 0;

void setRelay(bool on) {
  relayOn = on;
  digitalWrite(RELAY_PIN, (on != RELAY_ACTIVE_LOW) ? HIGH : LOW);
}

// HTTPS with certificate verification. No Firebase login is used in this demo.
int firebaseRequest(const char* path, const char* method, const String& body, String& response) {
  WiFiClientSecure client;
  client.setCACert(FIREBASE_ROOT_CA);
  client.setHandshakeTimeout(5);
  HTTPClient http;
  http.setConnectTimeout(5000);
  http.setTimeout(5000);
  if (!http.begin(client, String(FIREBASE_URL) + "/devices/" + DEVICE_ID + path)) return -1;

  int code;
  if (strcmp(method, "GET") == 0) {
    code = http.GET();
  } else {
    http.addHeader("Content-Type", "application/json");
    code = http.sendRequest(method, body);
  }
  response = code > 0 ? http.getString() : String();
  http.end();
  return code;
}

void readRelay() {
  String value;
  int code = firebaseRequest("/relay.json", "GET", "", value);
  value.trim();
  // A missing value, invalid value, or request error switches the relay OFF.
  setRelay(code == 200 && value == "true");
  Serial.printf("Relay: %s\n", relayOn ? "ON" : "OFF");
  if (code != 200) Serial.printf("Firebase relay read failed: HTTP %d\n", code);
}

void sendSensor() {
  float temperature = dht.readTemperature();
  float humidity = dht.readHumidity();
  if (isnan(temperature) || isnan(humidity)) {
    Serial.println("DHT11 read failed. Check the wiring.");
    return;
  }

  // Use the NTP-synchronized sample time (Unix milliseconds) as the history key.
  struct timeval sampledAt;
  gettimeofday(&sampledAt, nullptr);
  char historyKey[24];
  snprintf(historyKey, sizeof(historyKey), "%llu",
           static_cast<unsigned long long>(sampledAt.tv_sec) * 1000ULL + sampledAt.tv_usec / 1000);

  String reading = "{\"temperature\":" + String(temperature, 1) +
                   ",\"humidity\":" + String(humidity, 1) +
                   ",\"timestamp\":{\".sv\":\"timestamp\"}}";
  // A multi-path PATCH updates latest values and adds one history record together.
  String data = "{\"temperature\":" + String(temperature, 1) +
                ",\"humidity\":" + String(humidity, 1) +
                ",\"timestamp\":{\".sv\":\"timestamp\"},\"history/" + historyKey + "\":" + reading + "}";
  String response;
  // Only this history key is written; earlier records and relay are preserved.
  int code = firebaseRequest(".json", "PATCH", data, response);
  Serial.printf("Temperature: %.1f C | Humidity: %.1f %% | Firebase HTTP: %d\n",
                temperature, humidity, code);
  if (code == 200) Serial.printf("History saved: /devices/%s/history/%s\n", DEVICE_ID, historyKey);
  if (code == 401 || code == 403) Serial.println("Check Firebase database rules (see README).");
}

void setup() {
  Serial.begin(115200);
  Serial.printf("Device ID: %s\n", DEVICE_ID);
  digitalWrite(RELAY_PIN, RELAY_ACTIVE_LOW ? HIGH : LOW);
  pinMode(RELAY_PIN, OUTPUT);
  setRelay(false);
  dht.begin();

  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.begin(WIFI_SSID); // Open Wi-Fi: no password.
  lastWiFiAttempt = millis();
  Serial.println("Connecting to myUUM_Guest...");
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    setRelay(false);
    if (millis() - lastWiFiAttempt >= 15000) {
      lastWiFiAttempt = millis();
      WiFi.disconnect();
      WiFi.begin(WIFI_SSID);
      Serial.println("Retrying Wi-Fi...");
    }
    delay(10);
    return;
  }

  // A correct clock is required to verify the HTTPS certificate.
  static bool clockStarted = false;
  if (!clockStarted) {
    configTime(0, 0, "pool.ntp.org", "time.google.com");
    clockStarted = true;
    Serial.println("Wi-Fi connected. Synchronizing clock...");
  }
  if (time(nullptr) < 1700000000) { delay(10); return; }

  if (millis() - lastRelay >= 2000) {
    lastRelay = millis();
    readRelay();
  }
  if (millis() - lastSensor >= 5000) {
    lastSensor = millis();
    sendSensor();
  }
  delay(10);
}
