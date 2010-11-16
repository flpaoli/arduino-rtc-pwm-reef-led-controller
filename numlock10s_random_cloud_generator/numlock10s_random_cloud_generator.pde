// Set up RTC
#include "Wire.h"
#define DS1307_I2C_ADDRESS 0x68

// Temperature Sensor

#include <avr/pgmspace.h>
#define THERM_PIN   0  // 10ktherm & 10k resistor as divider.

int fanPin =  3;
int fanVal;
int fanTemp = 300;    // Temp Fans turn on
int offTemp = 600;   // Temp LEDs turn off

// RTC variables
byte second, rtcMins, oldMins, rtcHrs, oldHrs, dayOfWeek, dayOfMonth, month, year, psecond; 


// LED variables (Change to match your needs)
byte bluePins[]      =  {9, 10, 11};  // pwm pins for blues
byte whitePins[]     =  {5, 6};       // pwm pins for whites

byte blueChannels    =        3;    // how many PWMs for blues (count from above)
byte whiteChannels   =        2;    // how many PWMs for whites (count from above)

int startOffset      =        0;   // offset for start times
int colourOffset     =        15;   // offest for whites after blues start

byte blueLevel[]       =      {100, 100, 100};  // max intensity for Blue LED's in %
byte whiteLevel[]      =      {100, 100};  // max intensity for White LED's in %


// Month Data for Start, Stop, Photo Period and Fade (based off of actual times, best not to change)

int daysInMonth[12] = {31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};  //Days in each month

int minMinuteStart[12] = {310, 332, 348, 360, 372, 386, 394, 387, 364, 334, 307, 298}; //Minimum start times in each month
int maxMinuteStart[12] = {331, 347, 360, 372, 386, 394, 388, 365, 335, 308, 298, 309}; //Max start time in each month

int minMinuteFade[12] = {350, 342, 321, 291, 226, 173, 146, 110, 122, 139, 217, 282}; //Minimum fade time in each month
int maxMinuteFade[12] = {342, 321, 291, 226, 173, 146, 110, 122, 139, 217, 282, 350}; //Max fade time in each month

int minMinuteStop[12] = {1122, 1120, 1102, 1073, 1047, 1034, 1038, 1050, 1062, 1071, 1085, 1105}; //minimum stop times each month
int maxMinuteStop[12] = {1121, 1103, 1074, 1048, 1034, 1038, 1050, 1061, 1071, 1084, 1104, 1121}; //maximum stop times each month


// Weather variables

int weather = 1;  // 0 off, 1 on

int clearDays[12] = {15, 12, 20, 23, 28, 37, 43, 48, 51, 41, 29, 23};
int cloudyDays[12] = {60, 61, 62, 60, 64, 63, 68, 66, 63, 54, 52, 53}; 

int day = random(1,101);
int fadeOn, fadeOff, time, pause, value, count, cloud;
long start, finish;


// Other variables.

int minCounter;  // counter that resets at midnight. Don't change this.
long secCounter;
int fadeDuration;  // minutes to fade - calculated by map above
int ledStartMins;  // minute to start led’s - calculated by map above
int ledStopMins;  // minute to stop led’s - calculated by map above
byte blueMax[]      =      {0, 0, 0};  // used for overtemp protection
byte whiteMax[]     =      {0, 0};  // used for overtemp protection

/****** LED Functions ******/
/***************************/

//function to set LED brightness according to time of day

byte setLed(
int mins,    // current time in minutes
byte ledPin,  // pin for this channel of LEDs
int start,   // start time for this channel of LEDs
int fade,    // fade duration for this channel of LEDs
int stop,    // stop time for this channel of LEDs
byte ledMax,  // max value for this channel of LEDs
long begin,   // time cloud cycle begins in seconds
long secs,    // current time in seconds
int on,       // time for cloud to fade on in seconds
int off,      // time for cloud to fade off in seconds
long time     // time of cloud

// max value for this channel
)  {
  byte ledVal = 255;
  if (mins <= start || mins >= stop)  //this is when the LEDs are off, thus ledVal is 255;
  {
    ledVal = 255;
  }
  if (mins > start && mins <= start + fade) //this is sunrise 
  {
    ledVal =  map(mins, start, start + fade, 255, ledMax);
  }
  if (mins > start + fade && mins < stop - fade && weather == 1)
  {ledVal = ledMax;
    if (count == 1){
    if (secs >= begin && secs <= begin + fadeOn)
    {
      ledVal = map(secs, begin, begin + on, ledMax, value);
    }
    if (secs > begin + on && secs <= begin + on + time)
    {
      ledVal = value;
    }
    if (secs > begin + on + time && secs <= begin + on + time + off)
    { 
      ledVal = map(secs, begin + on + time, begin + on + time + off, value, ledMax);
    }
    if (secs > begin + on + time + off)
    {
      ledVal = ledMax;
    }
    if (secs >= finish)
    {
      count = 0;
    }
    } 
  }
  if (mins > start + fade && mins < stop - fade && weather == 0)
    {
      ledVal = ledMax;
    }
  if (mins < stop && mins >= stop - fade)  //this is the sunset
  {
    ledVal = map(mins, stop - fade, stop, ledMax, 255);
  }
  analogWrite(ledPin, ledVal);
  return ledVal;   
} 

/***** RTC Functions *******/
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
    secCounter = (long)minCounter * 60 + (long)second;
    
  // Thermal

  int therm;   
  therm = analogRead(THERM_PIN)-238;

  // Fans

  if (therm >= fanTemp){
    fanVal = map(therm, fanTemp, offTemp, 0, 255);
    analogWrite(fanPin, fanVal);
  }
  if (therm < fanTemp){
    analogWrite(fanPin, 0);
  }
  if (therm > offTemp){
    analogWrite(fanPin, 255);
  }

  // Start and Stop Times, Fade Time Functions

  ledStartMins = map(dayOfMonth, 1, daysInMonth[month-1], minMinuteStart[month-1], maxMinuteStart[month-1]) + startOffset; //LED Start time
  fadeDuration = map(dayOfMonth, 1, daysInMonth[month-1], minMinuteFade[month-1], maxMinuteFade[month-1]); //LED Fade time
  ledStopMins = map(dayOfMonth, 1, daysInMonth[month-1], minMinuteStop[month-1], maxMinuteStop[month-1]) + startOffset; // LED Stop time

  // LED Max Level Functions - % to PWM

  int t;
  for (t = 0; t < blueChannels; t++)
  {
    blueMax[t] = map(blueLevel[t], 0, 100, 255, 0);
  }
  for (t = 0; t < whiteChannels; t++)
  {
    whiteMax[t] = map(whiteLevel[t], 0, 100, 255, 0);
  }

  // Overtemp shutdown

  if (therm >= offTemp)
  {
    int t;
    for (t = 0; t < blueChannels; t++)
    {
      blueMax[t] = 255;
    }
    for (t = 0; t < whiteChannels; t++)
    {
      whiteMax[t] = 255;
    }
  }

// Weather Functions

if (minCounter == 0 && second == 0){
      {
      day = random(1,101);
      }
}  
if (count == 0){
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

    fadeOn = random(5,8); // Fade on of cloud is seconds
    fadeOff = random(5,8); // Fade off of cloud is seconds
    time = random(30,300); // Length of cloud in seconds
    pause = random(5,300); // Time between clouds in seconds
    start = secCounter; // Sets cycle start time
    //day = random(1,101); // Use to calculate new day value each cycle (normally off - used for testing)
    finish = start + fadeOn + time + fadeOff + pause; // Sets cylce finish time in seconds
    count = 1;
  }

  // LED State and Serial Print
  if (psecond != second){
    psecond = second;
    // set LED states
    Serial.print("Date - ");
    Serial.print(dayOfMonth,DEC);
    Serial.print("/");
    Serial.print(month,DEC);
    Serial.print("/");
    Serial.println(year,DEC);
    Serial.print("Time - ");   
    Serial.print(rtcHrs,DEC);
    Serial.print(":");
    Serial.print(rtcMins,DEC);
    Serial.print(":");
    Serial.println(second,DEC);
    Serial.print("Temp - ");
    Serial.print(therm / 10.,1);
    Serial.print((char)176);
    Serial.println(" C");
    Serial.println("");
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
    update_leds();
  }
  delay(50);
}


void update_leds( void ){
  int i;
  byte ledVal;
  for (i = 0; i < blueChannels; i++){
    ledVal = setLed(minCounter, bluePins[i], ledStartMins, fadeDuration, ledStopMins, blueMax[i], start, secCounter, fadeOn, fadeOff, time);
  }
  for (i = 0; i < whiteChannels; i++){
    ledVal = setLed(minCounter, whitePins[i], ledStartMins + colourOffset, fadeDuration, ledStopMins - colourOffset, whiteMax[i], start, secCounter, fadeOn, fadeOff, time);   
  }
}  
