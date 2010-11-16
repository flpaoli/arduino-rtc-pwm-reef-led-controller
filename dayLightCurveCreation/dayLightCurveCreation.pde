/**
 * Test sketch
 *
 * Create a day's Light curve by combining a basic sunrise/level/sunset curve
 * with random clouds which reduce light intensity.
 *
 * Store the curve in a "Light Waypoint" format
 *
 * Parts of this source code are based or inspired on Numlock10 (Jason) ReefCentral user's
 * Aug 27th post: http://www.reefcentral.com/forums/showpost.php?p=17570550&postcount=234
 *
 **/

// Set up RTC
#include "Wire.h"
#define DS1307_I2C_ADDRESS 0x68

// RTC variables
byte second, rtcMins, oldMins, rtcHrs, oldHrs, dayOfWeek, dayOfMonth, month, year;
byte prevDayOfMonth;
byte prevSecond;
int  pMinCounter;

// Month Data for Start, Stop, Photo Period and Fade (based off of actual times, best not to change)
//Days in each month
int daysInMonth[12] = {31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};  

//Minimum and Maximum sunrise start times in each month
int minSunriseStart[12] = {296, 321, 340, 357, 372, 389, 398, 389, 361, 327, 297, 285}; 
int maxSunriseStart[12] = {320, 340, 356, 372, 389, 398, 389, 361, 327, 297, 285, 296}; 

//Minimum and Maximum sunset stop times each month
int minSunsetFinish[12] = {1126, 1122, 1101, 1068, 1038, 1022, 1025, 1039, 1054, 1068, 1085, 1108}; 
int maxSunsetFinish[12] = {1122, 1101, 1068, 1038, 1022, 1025, 1039, 1054, 1068, 1085, 1108, 1126}; 

//Minimum and Maximum sunrise or sunset fade duration in each month
int minFadeDuration[12] = {350, 342, 321, 291, 226, 173, 146, 110, 122, 139, 217, 282}; 
int maxFadeDuration[12] = {342, 321, 291, 226, 173, 146, 110, 122, 139, 217, 282, 350}; 

// Weather variables
//int oktas[9] = {255, 239, 223, 207, 191, 175, 159, 143, 128}; // Cloud Values, original range
int oktas[9] = { 100, 94, 87, 81, 75, 69, 62, 56, 50 };         // Cloud Values in percentage
// I was going to use a daily random number from 1-100 generated at midnight.
// So for January 1-15 was clear, so 16-60 was cloudy and 61-100 would be mixed. 
int clearDays[12] = {15, 12, 20, 23, 28, 37, 43, 48, 51, 41, 29, 23};    // From 0 to clearDays = clear day (oktas 0..1)
int cloudyDays[12] = {60, 61, 62, 60, 64, 63, 68, 66, 63, 54, 52, 53};   // From clearDays to cloudyDays = cloudy day (oktas 4..8)
                                                                         // From cloudyDays to 100 = mixed day (oktas 2..3)

// Definition of a light waypoint
struct _waypoint {
  int time;        // in minutes, 1h = 60min, 24h = 1440min
  byte level;      // in percentage, 0 to 100
};

_waypoint currentSegmentStartWp;
_waypoint currentSegmentFinishWp;
float currentSegmentSlope;
int currentSegmentIndex;

// Use the definitions below to dim your LEDs in order to
// reach the desired color temperature.
//
// max intensity for Blue LED's in percentage
#define BLUE_MAX 100.0
// max intensity for White LED's in percentage
#define WHITE_MAX 100.0

// LED variables (Change to match your needs)
#define BLUE_CHANNELS 3
#define WHITE_CHANNELS 2
byte bluePins[BLUE_CHANNELS]      =  {9, 10, 11};  // pwm pins for blues
byte whitePins[WHITE_CHANNELS]    =  {5, 6};       // pwm pins for whites                                                                    

//Cloud shape curve
#define CLOUD_SHAPE_POINTS 6
_waypoint cloudShape[CLOUD_SHAPE_POINTS] = {
  { 0, 0 } ,
  { 1, 50 } ,
  { 5, 40 } ,
  { 12, 80 } ,
  { 14, 70 } ,
  { 15, 0 } 
};

// Light waypoints
#define MAX_WAYPOINTS 90
_waypoint todaysCurve[MAX_WAYPOINTS];  // White light value at waypoint
byte todaysCurveSize;                  // how many waypoints the day will have
boolean todayHasThunderstorm;          // True/False indicator if today has a thunderstorm
int thunderStormStart;
int thunderStormFinish;

// Starting time for the day's clouds (maximum of 10 for this test)
#define MAX_CLOUDS 10
int todaysClouds[MAX_CLOUDS];
byte todaysNumOfClouds;


/*****************************************************
 * Caclaulates a segment's slope based on the start
 * and finish waypoints
 **/ 
float calcSlope(int startTime,
    byte startLevel, 
    int finishTime,
    byte finishLevel)
{
      return (float) (finishLevel - startLevel) / (float) (finishTime - startTime);
}


/*************************************
 * Plan a new day
 * This is the function that is called when we enter a new day, it decides
 * what the day's waypoint curve will look like, in effect "programming"
 * the day's light levels
 **/
void planNewDay( byte aMonth, byte aDay ) {

  Serial.println("PLAN NEW DAY ----------------------");

  //------------- BASIC CURVE ------------- 
  
  // for this test we'll use a simple trapezoid curve of 6 waypoints
  
  _waypoint basicDayCurve[6];
  int basicDayCurveSize = 6;

  int fadeDuration = map(aDay, 1, daysInMonth[aMonth-1], minFadeDuration[aMonth-1], maxFadeDuration[aMonth-1]);
  int sunriseStart = map(aDay, 1, daysInMonth[aMonth-1], minSunriseStart[aMonth-1], maxSunriseStart[aMonth-1]);
  int sunriseFinish = sunriseStart + fadeDuration;

  int sunsetFinish = map(aDay, 1, daysInMonth[aMonth-1], minSunsetFinish[aMonth-1], maxSunsetFinish[aMonth-1]);
  int sunsetStart = sunsetFinish - fadeDuration;

  Serial.print("sunriseStart : ");
  Serial.print(sunriseStart, DEC);
  Serial.print(", sunriseFinish:");
  Serial.print(sunriseFinish, DEC);
  Serial.print(", sunsetStart  : ");
  Serial.print(sunsetStart, DEC);
  Serial.print("sunsetFinish : ");
  Serial.println(sunsetFinish, DEC);
  
  basicDayCurve[0].time = 0;
  basicDayCurve[0].level = 0;
  
  basicDayCurve[1].time = sunriseStart;
  basicDayCurve[1].level = 0;
  
  basicDayCurve[2].time = sunriseFinish;
  basicDayCurve[2].level = WHITE_MAX;
  
  basicDayCurve[3].time = sunsetStart;
  basicDayCurve[3].level = WHITE_MAX;
  
  basicDayCurve[4].time = sunsetFinish;
  basicDayCurve[4].level = 0;
  
  basicDayCurve[5].time = 1440;
  basicDayCurve[5].level = 0;
  
  //------------- CLOUDS  ------------- 
  boolean moreClouds;

  // In future versions the clouds section should determine from weather
  // data now many clouds to expect for the day, then calculate them
  // But in this version we're hard coding them just for testing purposes
  
  todaysNumOfClouds = 3;
  // Add a cloud when we are ramping up
  todaysClouds[0] = sunriseStart + 200;
  
  // Add a cloud when we are at the stable level
  todaysClouds[1] = sunriseFinish + 50;
  
  // Add a cloud slightly before we start sunsetting,
  // in order to check cloud intersection with basic curve waypoints
  todaysClouds[2] = sunsetStart - 10;
  
  // Pepare for the first iteration of the curve bulding loop
  if (todaysNumOfClouds > 0) {
    moreClouds = true;
  } else {
    moreClouds = false;
  }
  
  //------------- BUILD TODAY'S CURVE  ------------- 
  int nextWpIndex = 0;
  int cloudIndex = 0;

  // Every curve starts with 0,0
  todaysCurve[0].time=0;
  todaysCurve[0].level=0;
  nextWpIndex = 1;

  //Serial.println("Index, StartTime, StartLevel, FinishTime, FinishLevel:");

  boolean cloudStartedIntersectingSegment = false;

  // Go through the basic curve and fit the clouds into it
  for (int nextBasicWpIndex=1; nextBasicWpIndex < basicDayCurveSize; nextBasicWpIndex++) {
    _waypoint segmentStartWp;
    _waypoint segmentFinishWp;
    float segmentSlope;

    segmentStartWp = basicDayCurve[nextBasicWpIndex-1];  // Previous waypoint
    segmentFinishWp = basicDayCurve[nextBasicWpIndex];   // Next waypoint
    
    //Serial.print(nextBasicWpIndex, DEC);
    //Serial.print(", ");
    //Serial.print(segmentStartWp.time, DEC);
    //Serial.print(", ");
    //Serial.print(segmentStartWp.level, DEC);
    //Serial.print(", ");
    //Serial.print(segmentFinishWp.time, DEC);
    //Serial.print(", ");
    //Serial.println(segmentFinishWp.level, DEC);
    
    // Calculate the slope
    segmentSlope = calcSlope(segmentStartWp.time, segmentStartWp.level, segmentFinishWp.time, segmentFinishWp.level);

    // Do we still have clouds to insert today?
    if (moreClouds) {
      // Does the next cloud intersect this segment?
      if (todaysClouds[cloudIndex] <= segmentFinishWp.time) {
        // Ok, there is a cloud starting before the end of this segment
        //Serial.print("Starting cloud #");
        //Serial.println(cloudIndex, DEC);
  
        // We need to loop through the cloud, being careful to change segment
        // at the right time if the cloud continues after this segment's end
        for (int cloudShapeIndex=0; cloudShapeIndex < CLOUD_SHAPE_POINTS; cloudShapeIndex++) {
          float nextCloudWpReductionFactor;
  
          if (cloudStartedIntersectingSegment) {
            cloudShapeIndex++;
            cloudStartedIntersectingSegment = false;
          }
          
          // Calculate how much the cloud should reduce the light at this waypoint
          nextCloudWpReductionFactor = (100.0 - (float) cloudShape[cloudShapeIndex].level)/100.0;
    
          // The waypoint's time is the start of the cloud plus the cloud shape wp offset (time field)
          todaysCurve[nextWpIndex].time = todaysClouds[cloudIndex] + cloudShape[cloudShapeIndex].time;
          // The waypoint's level is the intersection of the slope with the cloud time vertical
          // with the cloud shape reduction factor applied to it
          todaysCurve[nextWpIndex].level =  segmentStartWp.level + (byte) (segmentSlope * ((float) (todaysCurve[nextWpIndex].time - segmentStartWp.time)));
          todaysCurve[nextWpIndex].level = (byte) (nextCloudWpReductionFactor * (float) todaysCurve[nextWpIndex].level);
          nextWpIndex++;
          
          // Now find out if the next cloud waypoint is still inside the
          // current basic curve segment
          // BUT WATCH OUT FOR END OF CLOUD, only do this if the cloud hasn't finished
          if (cloudShapeIndex < (CLOUD_SHAPE_POINTS - 1)) { 
            // Ok, cloud still has at least one more waypoint....
            //Serial.println("Ok, cloud still has at least one more waypoint....");
            
            //Serial.println("todaysClouds[cloudIndex] / cloudShape[cloudShapeIndex + 1].time / segmentFinishWp.time)");
            //Serial.print(todaysClouds[cloudIndex], DEC);
            //Serial.print(" / ");
            //Serial.print(cloudShape[cloudShapeIndex + 1].time, DEC);
            //Serial.print(" / ");
            //Serial.println(segmentFinishWp.time, DEC);
            
            if (todaysClouds[cloudIndex] + cloudShape[cloudShapeIndex + 1].time > segmentFinishWp.time) {
              // Humm, the cloud spans more than one segment....
              // .... need to move to the next segment now
              //Serial.println("---------> Humm, the cloud spans more than one segment....");
              nextBasicWpIndex++;
              
              segmentStartWp = segmentFinishWp;               // Previous waypoint
              segmentFinishWp = basicDayCurve[nextBasicWpIndex];   // Next waypoint
              // Calculate the slope
              segmentSlope = calcSlope(segmentStartWp.time, segmentStartWp.level, segmentFinishWp.time, segmentFinishWp.level);
              
              //Serial.print(nextBasicWpIndex, DEC);
              //Serial.print(", ");
              //Serial.print(segmentStartWp.time, DEC);
              //Serial.print(", ");
              //Serial.print(segmentStartWp.level, DEC);
              //Serial.print(", ");
              //Serial.print(segmentFinishWp.time, DEC);
              //Serial.print(", ");
              //Serial.println(segmentFinishWp.level, DEC);
            }
          }
        }
  
        // Prepare next cloud for loop
        if (cloudIndex < (todaysNumOfClouds-1)) {
          // Only move the cloud index forward if we still have clouds to insert into the curve
          cloudIndex++;
        } else {
          moreClouds = false;
        }

        //Serial.println("End of cloud....");
        // End of cloud, set the next waypoint as the segment's Finish
        // But only if there is no other cloud starting before that waypoint
        // becasue if there is, it's starting point should be the next waypoint
        if (moreClouds) {
  
          //Serial.println("But have more clouds...");
          // Does the next cloud intersect this segment?
          if (todaysClouds[cloudIndex] <= segmentFinishWp.time) {

            //Serial.println("... and it intersects the active segment!");
            // The waypoint's time is the start of the cloud plus the cloud shape wp offset (time field)
            todaysCurve[nextWpIndex].time = todaysClouds[cloudIndex] + cloudShape[0].time;
            // The waypoint's level is the intersection of the slope with the cloud time start vertical
            todaysCurve[nextWpIndex].level =  segmentStartWp.level + (byte) (segmentSlope * ((float) (todaysCurve[nextWpIndex].time - segmentStartWp.time)));
            nextWpIndex++;
            
            // Very important to wind backwards the nextBasicWpIndex because we're going
            // to loop now through the basicDayCurve but the cloud must stay in the
            // same segment for now
            nextBasicWpIndex--;
            cloudStartedIntersectingSegment = true;

          } else {
            
            //Serial.println("... but it doesn't intersect this segment, next waypoint is segment's finish");
  
            //... but it doesn't intersect this segment, next waypoint is segment's finish
            todaysCurve[nextWpIndex] = segmentFinishWp;
            nextWpIndex++;
          }

        } else {
          //Serial.println("OK, no other cloud, next waypoint is segment's finish");

          // OK, no other cloud, next waypoint is segment's finish
          todaysCurve[nextWpIndex] = segmentFinishWp;
          nextWpIndex++;
        }
        
      } else {

        //Serial.println("No cloud right now, just set the waypoint as the end of the segment");
        // No cloud right now, just set the waypoint as the end of the segment
        todaysCurve[nextWpIndex] = basicDayCurve[nextBasicWpIndex];
        nextWpIndex++;
      }
      
    } else {
      //Serial.println("No clouds at all, just set the waypoint as the end of the segment");
      // No clouds at all, just set the waypoint as the end of the segment
      todaysCurve[nextWpIndex] = basicDayCurve[nextBasicWpIndex];
      nextWpIndex++;
    }
  }
  
  //After creating a new curve you must set the current segment's
  //start and finish waypoints or the algorythm will be lost
  currentSegmentStartWp = todaysCurve[0];
  currentSegmentFinishWp = todaysCurve[1];
  currentSegmentIndex = 0;
  todaysCurveSize = nextWpIndex;
}

/*****************************************************
 * Print out to the serial port today's curve
 **/ 
void dumpCurve( void ) {
  Serial.println("DUMP CURVE ------------------------");
  Serial.print("month: ");
  Serial.print(month, DEC);
  Serial.print(", day: ");
  Serial.println(dayOfMonth, DEC);
  
  Serial.println("Index, Time, Level");
  for (int i=0; i < todaysCurveSize; i++) {
     Serial.print(i, DEC);
     Serial.print(", ");
     Serial.print(todaysCurve[i].time, DEC);
     Serial.print(", ");
     Serial.print(todaysCurve[i].level, DEC);
     Serial.println();
  }
  Serial.println("-----------------------------");
}


/****************************************************************
 * Update all the LED channels we have connected to the Arduino
 * with the right light value
 * 
 * For this function the bluePwmLevel and whitePwmLevel
 * are NOT expressed in percentage, but in Arduino's
 * PWM duty cycle 0-255 range
 *****************************************************************/
void updateLeds(byte bluePwmLevel, byte whitePwmLevel) {
  for (int i = 0; i < BLUE_CHANNELS; i++) {
    analogWrite(bluePins[i], bluePwmLevel);
  }
  for (int i = 0; i < WHITE_CHANNELS; i++) {
    analogWrite(whitePins[i], whitePwmLevel);
  }
}  

/*****************************************************************
 * Return the current white LED level expressed as a percentage
 * with 0-100 range.  This function uses the WHITE_MAX value
 * to dim the output range.
 *
 * now parameter is current time expressed in minutes since 
 * start of day
 *
 * the return is a percentage value, 0-100
 */
byte findCurrentWhiteLevel(int now) {
  
  float result;  
  
  // Remember to reprogram to finsd the first segment
  
  //Serial.print("Now=");
  //Serial.print(now, DEC);
  //Serial.print(", finishTime=");
  //Serial.println(currentSegmentFinishWp.time, DEC);

  
  // If this instant in time is still inside the current curve segment
  // just apply the slope math to find the exact light level or....
  if (now > currentSegmentFinishWp.time) {
    // ... we have moved into the next curve segment, therefore we need to fetch it

    // But this needs to be a while loop because we might have skipped one segment
    // if the Arduino was busy doing something else (in future more complex editions
    // of this code that might happen)

    while ((now > currentSegmentFinishWp.time) && (currentSegmentIndex < (todaysCurveSize - 1))) {
      
      // Get the next segment
      currentSegmentStartWp = currentSegmentFinishWp;
      currentSegmentIndex++;
      currentSegmentFinishWp = todaysCurve[currentSegmentIndex + 1];

      // Calculate slope
      currentSegmentSlope = calcSlope(currentSegmentStartWp.time, currentSegmentStartWp.level, currentSegmentFinishWp.time, currentSegmentFinishWp.level);
    }
  }
   

  //Serial.print("TodaysCurveSize=");
  //Serial.print(todaysCurveSize, DEC);
  //Serial.print(", Index=");
  //Serial.print(currentSegmentIndex, DEC);
  //Serial.print(", time=");
  //Serial.print(currentSegmentStartWp.time, DEC);
  //Serial.print(", level=");
  //Serial.print(currentSegmentStartWp.level, DEC);
  //Serial.print(", slope=");
  //Serial.println(currentSegmentSlope, DEC);

  // Determine light level for now, using the current start waypoint and curve slope 
  result = (float) currentSegmentStartWp.level + (currentSegmentSlope * ((float) (now - currentSegmentStartWp.time)));
  
  //Serial.print("result=");
  //Serial.print(result, DEC);
  //Serial.print("->");
  //Serial.println((byte) result, DEC);

  // Use WHITE_MAX to dim light to maximum desired level
  return (byte) (WHITE_MAX/100.0 * result);
}


/*****************************************************
 * Convert binary coded decimal to normal decimal
 * numbers
 **/ 
byte bcdToDec(byte val)
{
  return ( (val/16*10) + (val%16) );
}

/*****************************************************
 * Gets the date and time from the ds1307
 **/
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

/*************************************
 * Main Loop
 **/
void loop() {

  byte blueLevel;
  byte whiteLevel;
  int minCounter;
  
  // Get current instant of time
  getDateDs1307(&second, &rtcMins, &rtcHrs, &dayOfWeek, &dayOfMonth, &month, &year);

  // If day changes, recalculate curve
  if (prevDayOfMonth != dayOfMonth) {
    planNewDay(month, dayOfMonth);
    prevDayOfMonth = dayOfMonth;
    dumpCurve();
  }

  minCounter = rtcHrs * 60 + rtcMins;

  // ============== For testing purposes you can uncomment ============================================================
  // the line below and accellerate the day, making the whole
  // day go by in one minute, like a dry run.
  //
  minCounter = (second * 24);
  if (prevSecond > second) {
    // Day change, replan day
    planNewDay(month, dayOfMonth);
    prevDayOfMonth = dayOfMonth;
    dumpCurve();
  }    
  prevSecond = second;
  // ============== End of "For testing purposes" =====================================================================

  // If one or more minutes elapsed, do something
  if (pMinCounter != minCounter) {
      pMinCounter = minCounter;

      whiteLevel = findCurrentWhiteLevel(minCounter);

      // For this test use the same levels for blue and white
      blueLevel = whiteLevel;
      
      // set LED states
      Serial.print("Time: ");
      Serial.print(rtcHrs, DEC);
      Serial.print(":");
      Serial.print(rtcMins, DEC);
      Serial.print(" (");
      Serial.print(minCounter, DEC);
      Serial.print("mins) -> W=");
      Serial.print(whiteLevel, DEC);
      Serial.print(", B=");
      Serial.println(blueLevel, DEC);

      // Remember parameters are 0-255
      updateLeds( (byte) ((float) blueLevel/100.0 * 255.0), (byte) (((float) whiteLevel)/100.0 * 255.0));
      
      if (todayHasThunderstorm) {
        if ((minCounter >= thunderStormStart) && (minCounter >= thunderStormFinish)) {
      
          /*
          // Lightning code posted by Numlock10@ReefCentral
          // 
          // http://www.reefcentral.com/forums/showpost.php?p=17542851&postcount=206
          //
          
          if (randNumber <= 25) {  //sets chance of lightning to "Dark" clouds
            var = 0;
            while(var < 10){analogWrite(led3Pin, 255);   // set 10 cycles, LED on
            analogWrite(led3Pin, 0);                     // set the LED off
            delay(random(0,1000));                       // off random time
            analogWrite(led3Pin, 255);                   // set the LED on
            delay(random(0,750));                        // on random time
            var++;}
          }
          */
        }
      }
  }  
}

/*************************************
 * SETUP
 **/
void setup()  { 
  
  Serial.begin(9600);

  // init I2C  
  Wire.begin();
  
  delay(1000);
  
  Serial.println("RESET VARIABLES -------------------");
  resetVariables();
  
} 

/*************************************
 * Reset the variables when we start
 * specially the arrays or memory positions
 * that need initialization.
 **/
void resetVariables( void ) {
  // Zero all the waypoints ....
  for (int i = 0; i<MAX_WAYPOINTS; i++) {
    todaysCurve[i].time = 0;
    todaysCurve[i].level = 0;
  }
  // ... and say the day has only one waypoint
  todaysCurveSize = 1;
  
  for (int i=0; i<MAX_CLOUDS; i++) {
    todaysClouds[i] = 0;
  }
  todaysNumOfClouds = 0;
  
  currentSegmentStartWp.time = 0;
  currentSegmentStartWp.level = 0;
  currentSegmentFinishWp.time = 1441;
  currentSegmentFinishWp.level = 0;
  currentSegmentSlope = 0.0;
  currentSegmentIndex = 0;

  pMinCounter = 0;  
}

