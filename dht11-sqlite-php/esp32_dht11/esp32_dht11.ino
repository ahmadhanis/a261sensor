#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <DHT.h>

const char* WIFI_SSID = "myUUM_Guest";
const char* DEVICE_ID = "esp32-01";  // Use a different ID for each ESP32.
const char* API_URL = "https://slum78.myddns.me/iot/dht11/insertdht.php";
constexpr uint8_t DHT_PIN = 4;
constexpr unsigned long SEND_INTERVAL_MS = 10000;
DHT dht(DHT_PIN, DHT11);

bool connectWiFi() {
  if (WiFi.status() == WL_CONNECTED) return true;
  Serial.print("Connecting to myUUM_Guest");
  WiFi.begin(WIFI_SSID);  // Open network: no password.
  unsigned long started = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - started < 20000) {
    delay(500);
    Serial.print(".");
  }
  Serial.println();
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi unavailable; will retry.");
    return false;
  }
  Serial.print("IP: ");
  Serial.println(WiFi.localIP());
  return true;
}

void setup() {
  Serial.begin(115200);
  dht.begin();
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  connectWiFi();
  delay(2000);  // Allow the sensor to settle before the first reading.
}

void loop() {
  if (connectWiFi()) {
    float humidity = dht.readHumidity();
    float temperature = dht.readTemperature();  // Celsius.
    if (isnan(humidity) || isnan(temperature)) {
      Serial.println("DHT11 read failed. Check wiring.");
    } else {
      WiFiClientSecure client;
      client.setInsecure();  // HTTPS without certificate verification, as requested.
      HTTPClient http;
      http.setConnectTimeout(10000);
      http.setTimeout(10000);
      if (http.begin(client, API_URL)) {
        http.addHeader("Content-Type", "application/json");
        String payload = String("{\"device_id\":\"") + DEVICE_ID
                       + "\",\"temperature\":" + String(temperature, 1)
                       + ",\"humidity\":" + String(humidity, 1) + "}";
        int status = http.POST(payload);
        Serial.printf("Temperature: %.1f C, humidity: %.1f %%\n", temperature, humidity);
        if (status > 0) {
          Serial.printf("HTTP %d: ", status);
          Serial.println(http.getString());
          if (status != 201) Serial.println("Reading was not confirmed as stored.");
        } else {
          Serial.println("Request failed: " + http.errorToString(status));
        }
        http.end();
      } else {
        Serial.println("Unable to start HTTP request.");
      }
    }
  }
  delay(SEND_INTERVAL_MS);
}
