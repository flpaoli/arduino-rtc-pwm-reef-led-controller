int ledPin = 9;    // LED connected to digital pin 9

int fadeValue;
int fadeDir;

void setup() {                
  Serial.begin(9600);

  // prints title with ending line break
  Serial.println("Startup"); 
  
  // initialize the digital pin as an output.
  // Pin 13 has an LED connected on most Arduino boards:
  pinMode(13, OUTPUT);     
  fadeValue = 0;
  fadeDir = 0;
}

void loop() {
  digitalWrite(13, HIGH);   // set the LED on
  Serial.println("On"); 
  delay(250);              // wait for a quarter of a second

  digitalWrite(13, LOW);    // set the LED off
  Serial.println("Off"); 
  delay(250);              // wait for a quarter of a second

  analogWrite(ledPin, fadeValue);
  if (fadeDir == 0) {      // Moving upwards
    fadeValue += 25;
    if (fadeValue > 255) {  // Reached limit? revert
      fadeValue = 255;
      fadeDir = 1;
    }
  } else {                 // Must be 1,moving downwards
    fadeValue -= 25;
    if (fadeValue < 0) {    // reached limit? revert
      fadeValue = 0;
      fadeDir = 0;
    }
  }

}
