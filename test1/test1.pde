int ledPin1 = 9;    // LED connected to digital pin 9
int ledPin2 = 9;    // LED connected to digital pin 9
boolean led13;

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
  led13=false;
}

void loop() {
  digitalWrite(13, led13);   // set the LED on
  led13=!led13;
  delay(20);              

  analogWrite(ledPin1, fadeValue);
  analogWrite(ledPin2, fadeValue);
  if (fadeDir == 0) {      // Moving upwards
    fadeValue += 2;
    if (fadeValue > 255) {  // Reached limit? revert
      fadeValue = 255;
      fadeDir = 1;
    }
  } else {                 // Must be 1,moving downwards
    fadeValue -= 2;
    if (fadeValue < 0) {    // reached limit? revert
      fadeValue = 0;
      fadeDir = 0;
    }
  }

}
