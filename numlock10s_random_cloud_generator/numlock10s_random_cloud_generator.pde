// Set up RTC
#include "Wire.h"
#define DS1307_I2C_ADDRESS 0x68

// RTC variables
byte second, rtcMins, oldMins, rtcHrs, oldHrs, dayOfWeek, dayOfMonth, month, year, psecond; 

// Weather variables

int clearDays[12] = {15, 12, 20, 23, 28, 37, 43, 48, 51, 41, 29, 23};
int cloudyDays[12] = {60, 61, 62, 60, 64, 63, 68, 66, 63, 54, 52, 53}; 

int day, fadeOn, fadeOff, time, pause, value, count, ledMax, cloud;
long start, finish;

// Other variables

long minCounter;  // counter that resets at midnight. Don't change this.
long secCounter;

// Weather Functions


/* RTC Functions *******/
/***************************/
// Convert normal decimal numbers to binary coded decimal
byte decToBcd(byte val)
{
  return ( (val/10*16) + (val%10) );
}

// Convert binary coded decimal to normal decimal numbers
byte bcdToDec(byte val)
{
  return ( (val/16*10) + (val%16) );
}

// Gets the date and time from the ds1307
void getDateDs1307(byte *second,
byte *minute,
byte *hour,
byte *dayOfWeek,
byte *dayOfMonth,
byte *month,
byte *year)
{
  Wire.beginTransmission(DS1307_I2C_ADDRESS);
  Wire.send(0);
  Wire.endTransmission();

  Wire.requestFrom(DS1307_I2C_ADDRESS, 7);

  *second     = bcdToDec(Wire.receive() & 0x7f);
  *minute     = bcdToDec(Wire.receive());
  *hour       = bcdToDec(Wire.receive() & 0x3f);
  *dayOfWeek  = bcdToDec(Wire.receive());
  *dayOfMonth = bcdToDec(Wire.receive());
  *month      = bcdToDec(Wire.receive());
  *year       = bcdToDec(Wire.receive());
}

void setup()  { 

  // init I2C  
  Serial.begin(57600);
  Wire.begin();

} 

/***** Main Loop ***********/
/***************************/
void loop(){
  getDateDs1307(&second, &rtcMins, &rtcHrs, &dayOfWeek, &dayOfMonth, &month, &year);

  minCounter = rtcHrs * 60 + rtcMins;
  secCounter = minCounter * 60 + second;
  // Weather Functions
  
  // Used to calculate day type at Midnight
  //if (minCounter == 0 && second == 0 || day == 0)
  //    {
  //    day = random(1,100);
  //    }

  if (count == 0){
    fadeOn = random(5,8); // Fade on of cloud is seconds
    fadeOff = random(5,8); // Fade off of cloud is seconds
    time = random(30,120); // Length of cloud in seconds
    pause = random(5,120); // Time between clouds in seconds
    start = secCounter; // Sets cycle start time
    day = random(1,100); // Use to calculate new day value each cycle (normally off - used for testing)
    
    if (day <= clearDays[month-1]) // Clear Day oktas 0 - 1
    {
      value = random(0,66);
    } 
    if (day > clearDays[month-1] && day <= cloudyDays[month-1]) // Cloudy Day oktas 6 - 8
    {
      value = random(132,200);
    } 
    if (day > cloudyDays[month-1]) // Normal Day oktas 2-5
    {
      value = random(0,132); 
    }
    finish = start + fadeOn + time + fadeOff + pause; // Sets cylce finish time in seconds
    count = 1;
  }
  
  if (count == 1){
    if (secCounter >= start && secCounter <= start + fadeOn)
    {
      cloud = map(secCounter, start, start + fadeOn, ledMax, value);
    }
    if (secCounter > start + fadeOn && secCounter <= start + fadeOn + time)
    {
      cloud = value;
    }
    if (secCounter > start + fadeOn + time && secCounter <= start + fadeOn + time + fadeOff)
    { 
      cloud = map(secCounter, start + fadeOn + time, start + fadeOn + time + fadeOff, value, ledMax);
    }
    if (secCounter == finish)
    {
      count = 0;
    }
  }
  analogWrite(11,cloud);
  analogWrite(9,cloud);
  analogWrite(5,cloud);

  if (psecond != second){
    psecond = second;
    Serial.print("Day Value - ");
    Serial.println(day);
    Serial.print("Fade on - ");
    Serial.print(fadeOn);
    Serial.println(" seconds");
    Serial.print("Length of cloud - ");
    Serial.print(time);
    Serial.println(" seconds");
    Serial.print("Fade off - ");
    Serial.print(fadeOff);
    Serial.println(" seconds");
    Serial.print("Pause before next cloud - ");
    Serial.print(pause);
    Serial.println(" seconds");
    Serial.print("Time cycle started - ");
    Serial.println(start);
    Serial.print("Time cycle will finish - ");
    Serial.println(finish);
    Serial.print("Value for cloud - ");
    Serial.println(value);
    Serial.print("Current value of LED's - ");
    Serial.println(cloud);
    Serial.print("Current time in seconds - ");
    Serial.println(secCounter);
    Serial.println("");
  }
  delay(1000);

}
