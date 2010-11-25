 // Set up RTC 
#include "Wire.h" 
#define DS1307_I2C_ADDRESS 0x68 

/*
// Temperature Sensor 

#include <avr/pgmspace.h> 
#define THERM_PIN   0  // 10ktherm & 10k resistor as divider. 

int fanPin =  3; 
int fanVal; 
int therm; 
int fanTemp = 300;    // Temp Fans turn on 
int offTemp = 600;   // Temp LEDs turn off 
*/

// RTC variables 
byte second, rtcMins, oldMins, rtcHrs, oldHrs, dayOfWeek, dayOfMonth, month, year, psecond;  


// LED variables (Change to match your needs) 
byte bluePins[]      =  {10, 11};  // PWM pins for blues - if you plan to use the photo stagger, please place the pins in the order you would like them to start 
byte whitePins[]     =  {3, 5, 6, 9};       // PWM pins for whites - if you plan to use the photo stagger, please place the pins in the order you would like them to start 

byte blueChannels    =        2;    // how many PWMs for blues (count from above) 
byte whiteChannels   =        4;    // how many PWMs for whites (count from above) 

int photoStagger     =        0;    //  offset for east - west delay on each channel in minutes 
int startOffset      =        0;    // offset for start times in minutes - used if you want to change the start and finish time of the cycle.  i.e move it to a later time in the day 
int colourOffset     =        15;   // offset for whites to start after blues start in minutes 

byte blueLevel[]       =      {255, 255};  // max intensity for Blue LED's 
byte whiteLevel[]      =      {255, 255, 255, 255};  // max intensity for White LED's 


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

float clearDay = 0.25; // Max cloud value on clear day (percent of max string value) 
float cloudyDay = 0.75; // Max cloud value on cloudy day (percent of max string value) 
float normalDay = 0.5; // Max cloud value on normal day (percent of max string value) 

byte value; 
int day, fadeOn, fadeOff, time, pause, count, cloud; 
long start, finish; 


// Other variables - Do not need to be changed. 

int minCounter;  // counter that resets at midnight 
long secCounter;  // counter for seconds - needed for weather 
int fadeDuration;  // minutes to fade - calculated by map above 
int ledStartMins;  // minute to start led’s - calculated by map above 
int ledStopMins;  // minute to stop led’s - calculated by map above 
byte blueMax[] = {0, 0};      // used for over temp protection 
byte whiteMax[] = {0, 0, 0, 0};    // used for over temp protection 
byte valueBlue[] = {0, 0};  // value for clouds 
byte valueWhite[] = {0, 0, 0, 0};   // value for clouds 

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
long time,     // time of cloud 
byte value,    // value for cloud 
int therm,     // tempature 
int offTemp    // tempature shudown 

// max value for this channel 
)  { 
  byte ledVal = 0;   
  if (mins <= start || mins >= stop)  //this is when the LEDs are off, thus ledVal is 255; 
  { 
    ledVal = 0; 
  } 
  if (mins > start && mins <= start + fade) //this is sunrise  
  { 
    ledVal =  map(mins, start, start + fade, 0, ledMax); 
  } 
  if (mins > start + fade && mins < stop - fade && weather == 1) 
  { 
    ledVal = ledMax; 
    if (count == 1){ 
      if (secs >= begin && secs < begin + fadeOn) 
      { 
        ledVal = map(secs, begin, begin + on, ledMax, value); 
      } 
      if (secs >= begin + on && secs < begin + on + time) 
      { 
        ledVal = value; 
      } 
      if (secs >= begin + on + time && secs < begin + on + time + off) 
      {  
        ledVal = map(secs, begin + on + time, begin + on + time + off, value, ledMax); 
      } 
      if (secs >= begin + on + time + off) 
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
    ledVal = map(mins, stop - fade, stop, ledMax, 0); 
  } 
//  if (therm >= offTemp) 
//  { 
//    ledVal = 0; 
//  } 
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
  randomSeed(analogRead(1)); 
}  

/***** Main Loop ***********/ 
/***************************/ 
void loop(){ 
  getDateDs1307(&second, &rtcMins, &rtcHrs, &dayOfWeek, &dayOfMonth, &month, &year); 

  minCounter = rtcHrs * 60 + rtcMins; 
  secCounter = (long)minCounter * 60 + (long)second; 

/*
  // Thermal 
   
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
*/
  // Start and Stop Times, Fade Time Functions 

  ledStartMins = map(dayOfMonth, 1, daysInMonth[month-1], minMinuteStart[month-1], maxMinuteStart[month-1]) + startOffset; //LED Start time 
  fadeDuration = map(dayOfMonth, 1, daysInMonth[month-1], minMinuteFade[month-1], maxMinuteFade[month-1]); //LED Fade time 
  ledStopMins = map(dayOfMonth, 1, daysInMonth[month-1], minMinuteStop[month-1], maxMinuteStop[month-1]) + startOffset; // LED Stop time 

  // Weather Functions 

  if (minCounter == 0 && second == 0 || day == 0){ 
    { 
      day = random(1,101); 
    } 
  }   
  if (count == 0){ 
    if (day <= clearDays[month-1]) // Clear Day 
    { 
      int t; 
      for (t = 0; t < blueChannels; t++) 
      {   
        valueBlue[t] = random(blueLevel[t]*clearDay,blueLevel[t]); 
      } 
      for (t = 0; t < whiteChannels; t++) 
      { 
        valueWhite[t] = random(whiteLevel[t]*clearDay,whiteLevel[t]); 
      } 
    } 
    if (day > clearDays[month-1] && day <= cloudyDays[month-1]) // Cloudy Day  
    { 
      int t; 
      for (t = 0; t < blueChannels; t++) 
      {   
        valueBlue[t] = random(blueLevel[t]*normalDay,blueLevel[t]*cloudyDay); 
      } 
      for (t = 0; t < whiteChannels; t++) 
      { 
        valueWhite[t] = random(whiteLevel[t]*normalDay,whiteLevel[t]*cloudyDay); 
      } 
    }  
    if (day > cloudyDays[month-1]) // Normal Day  
    { 
      int t; 
      for (t = 0; t < blueChannels; t++) 
      {   
        valueBlue[t] = random(blueLevel[t]*normalDay,blueLevel[t]); 
      } 
      for (t = 0; t < whiteChannels; t++) 
      { 
        valueWhite[t] = random(whiteLevel[t]*normalDay,whiteLevel[t]); 
      } 
    }   

    fadeOn = random(5,8); // Fade on of cloud in seconds 
    fadeOff = random(5,8); // Fade off of cloud in seconds 
    time = random(30,300); // Length of cloud in seconds 
    pause = random(5,300); // Time between clouds in seconds 
    start = secCounter; // Sets cycle start time 
    finish = start + fadeOn + time + fadeOff + pause; // Sets cylce finish time in seconds 
    count = 1; 
  } 
  

   
   
  int t; 
      for (t = 0; t < blueChannels; t++) 
      {   
        blueMax[t] = blueLevel[t]; 
      } 
      for (t = 0; t < whiteChannels; t++) 
      { 
        whiteMax[t] = whiteLevel[t]; 
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
    ledVal = setLed(minCounter, bluePins[i], ledStartMins + (photoStagger * (i+1)), fadeDuration, ledStopMins - (photoStagger * (i+1)), blueMax[i], start, secCounter, fadeOn, fadeOff, time, valueBlue[i], therm, offTemp); 
  } 
  for (i = 0; i < whiteChannels; i++){ 
    ledVal = setLed(minCounter, whitePins[i], ledStartMins + colourOffset + (photoStagger * (i+1)), fadeDuration, ledStopMins - colourOffset - (photoStagger * (i+1)), whiteMax[i], start, secCounter, fadeOn, fadeOff, time, valueWhite[i], therm, offTemp);    
  } 
}  
