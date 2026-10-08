#include <Arduino.h>

const int buttonPin = 0;  // the number of the pushbutton pin
const int ledPin = 2;     // the number of the LED pin

// Variables for storing states
int buttonState = 0;         // current state of the button
int lastButtonState = LOW;   // previous state of the button
int ledState = LOW;          // current state of the LED (LOW = OFF, HIGH = ON)

void setup() {
  Serial.begin(115200);
  // initialize the pushbutton pin as an input
  pinMode(buttonPin, INPUT);
  // initialize the LED pin as an output
  pinMode(ledPin, OUTPUT);
}

void loop() {
  // read the state of the pushbutton value
  buttonState = digitalRead(buttonPin);

  // check if the button state has changed from LOW to HIGH (a new press)
  if (buttonState != lastButtonState) {
    if (buttonState == HIGH) {
      // Toggle the LED state
      ledState = !ledState;
      digitalWrite(ledPin, ledState);
      
      // Print the current LED state to Serial
      Serial.print("LED State: ");
      Serial.println(ledState);
    }
    // Short delay for basic debounce
    delay(50);
  }

  // Save the current button state as the last state for the next loop
  lastButtonState = buttonState;
}