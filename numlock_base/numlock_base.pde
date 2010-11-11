/**
 * Original source code from Numlock10 ReefCentral user
 * posted in Aug 27th thread linked below:
 * http://www.reefcentral.com/forums/showpost.php?p=17570550&postcount=234
 **/
 
// Set up RTC
#include "Wire.h"
#define DS1307_I2C_ADDRESS 0x68

// RTC variables
byte second, rtcMins, oldMins, rtcHrs, oldHrs, dayOfWeek, dayOfMonth, month, year, psecond; 


// LED variables (Change to match your needs)
byte bluePins[]      =  {9, 10, 11};  // pwm pins for blues
byte whitePins[]     =  {5, 6};       // pwm pins for whites

byte blueChannels    =        3;    // how many PWMs for blues (count from above)
byte whiteChannels   =        2;    // how many PWMs for whites (count from above)
                                                                       
byte blueMax         =        255;  // max intensity for Blue LED's. 
byte whiteMax        =        255;  // max intensity for White LED's.

// Month Data for Start, Stop, Photo Period and Fade (based off of actual times, best not to change)

int daysInMonth[12] = {31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};  //Days in each month

int minMinuteStart[12] = {296, 321, 340, 357, 372, 389, 398, 389, 361, 327, 297, 285}; //Minimum start times in each month
int maxMinuteStart[12] = {320, 340, 356, 372, 389, 398, 389, 361, 327, 297, 285, 296}; //Max start time in each month

int minMinuteFade[12] = {350, 342, 321, 291, 226, 173, 146, 110, 122, 139, 217, 282}; //Minimum fade time in each month
int maxMinuteFade[12] = {342, 321, 291, 226, 173, 146, 110, 122, 139, 217, 282, 350}; //Max fade time in each month

int minMinuteStop[12] = {1126, 1122, 1101, 1068, 1038, 1022, 1025, 1039, 1054, 1068, 1085, 1108}; //minimum stop times each month
int maxMinuteStop[12] = {1122, 1101, 1068, 1038, 1022, 1025, 1039, 1054, 1068, 1085, 1108, 1126}; //maximum stop times each month

// Weather variables

/*int weather = 0;

int oktas[9] = {255, 239, 223, 207, 191, 175, 159, 143, 128}; // Cloud Values
int clearDays[12] = {15, 12, 20, 23, 28, 37, 43, 48, 51, 41, 29, 23};
int cloudyDays[12] = {60, 61, 62, 60, 64, 63, 68, 66, 63, 54, 52, 53}; 
int cloud1 = random(1,5);
int cloud2 = random(1,5);
*/
// Other variables.

int minCounter       =       0;  // counter that resets at midnight. Don't change this.
int fadeDuration     =       0;  // minutes to fade - calculated by map above
int ledStartMins     =       0;  // minute to start led’s - calculated by map above
int ledStopMins      =       0;  // minute to stop led’s - calculated by map above

/****** LED Functions ******/
/***************************/
//function to set LED brightness according to time of day
//function has three equal phases - ramp up, hold, and ramp down
byte setLed(int mins,    // current time in minutes
            byte ledPin,  // pin for this channel of LEDs
            int start,   // start time for this channel of LEDs
            //int period,  // photoperiod for this channel of LEDs
            int fade,    // fade duration for this channel of LEDs
            int stop,    // stop time for this channel of LEDs
            byte ledMax   // max value for this channel
            )  {
  byte ledVal = 0;
  if (mins <= start || mins >= stop)  {
    //this is when the LEDs are off, thus ledVal is 0;
    ledVal = 0;

  } else if (mins > start && mins <= start + fade) {
    //this is sunrise
    ledVal =  map(mins, start, start + fade, 0, ledMax);

  } else if (mins > start + fade && mins < stop - fade)  {
    // this is the level period
    ledVal = ledMax;

  } else if (mins < stop && mins >= stop - fade)  {
    //this is the sunset.
    ledVal = map(mins, stop - fade, stop, ledMax, 0);
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

// 1) Sets the date and time on the ds1307
// 2) Starts the clock
// 3) Sets hour mode to 24 hour clock
// Assumes you're passing in valid numbers.
//void setDateDs1307(byte second,        // 0-59
//                   byte minute,        // 0-59
//                   byte hour,          // 1-23
//                   byte dayOfWeek,     // 1-7
//                   byte dayOfMonth,    // 1-28/29/30/31
//                   byte month,         // 1-12
//                   byte year)          // 0-99
//{
//   Wire.beginTransmission(DS1307_I2C_ADDRESS);
//   Wire.send(0);
//   Wire.send(decToBcd(second));
//   Wire.send(decToBcd(minute));
//   Wire.send(decToBcd(hour));
//   Wire.send(decToBcd(dayOfWeek));
//   Wire.send(decToBcd(dayOfMonth));
//   Wire.send(decToBcd(month));
//   Wire.send(decToBcd(year));
//   Wire.endTransmission();
//}

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
void loop() {
  getDateDs1307(&second, &rtcMins, &rtcHrs, &dayOfWeek, &dayOfMonth, &month, &year);

  // Photo Period, Start Time, Fade Time Functions
  ledStartMins = map(dayOfMonth, 1, daysInMonth[month-1], minMinuteStart[month-1], maxMinuteStart[month-1]); //LED Start time
  fadeDuration = map(dayOfMonth, 1, daysInMonth[month-1], minMinuteFade[month-1], maxMinuteFade[month-1]); //LED Fade time
  ledStopMins = map(dayOfMonth, 1, daysInMonth[month-1], minMinuteStop[month-1], maxMinuteStop[month-1]); // LED Stop time
  
  // LED State and Serial Print
  if (psecond != second) {
      psecond = second;
      // set LED states
      minCounter = rtcHrs * 60 + rtcMins;
      Serial.print("Current Minutes - ");   
      Serial.println(minCounter);
      Serial.print("Start Time - ");
      Serial.println(ledStartMins);
      Serial.print("Fade - ");
      Serial.print(fadeDuration);
      Serial.println(" Minutes");
      Serial.print("Stop Time - ");
      Serial.println(ledStopMins);
      update_leds();
  }

  delay(50);
 }


void update_leds( void ) {
  int i;
  byte ledVal;
  for (i = 0; i < blueChannels; i++){
      ledVal = setLed(minCounter, bluePins[i], ledStartMins, fadeDuration, ledStopMins, blueMax);
  }
  for (i = 0; i < whiteChannels; i++){
      ledVal = setLed(minCounter, whitePins[i], ledStartMins, fadeDuration, ledStopMins, whiteMax);
      
  }
}  
