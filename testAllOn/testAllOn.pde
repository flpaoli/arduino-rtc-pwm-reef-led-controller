int ledPin1 = 9;    // LED connected to digital pin 9
int ledPin2 = 10;    // LED connected to digital pin 9
boolean led13;

void setup() {                
  Serial.begin(9600);

  // initialize the digital pin as an output.
  // Pin 13 has an LED connected on most Arduino boards:
  pinMode(13, OUTPUT);     
  led13=false;

  analogWrite(ledPin1, 255);
  analogWrite(ledPin2, 255);

}

void loop() {
  digitalWrite(13, led13);   // set the LED on
  led13=!led13;
  delay(250);              

}
