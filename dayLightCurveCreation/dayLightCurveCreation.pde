/**
 * Test sketch
 *
 * Create a day's Light curve by combining a basic sunrise/level/sunset curve
 * with random clouds which reduce light intensity.
 *
 * Store the curve in a "Light Waypoint" format
 **/

// Definition of a light waypoint
struct _waypoint {
  int time;        // in minutes, 1h = 60min, 24h = 1440min
  byte level;      // in percentage, 0 to 100
};

byte blueMax         =  100;  // max intensity for Blue LED's in percentage
byte whiteMax        =  100;  // max intensity for White LED's in percentage

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
//int oktas[9] = {255, 239, 223, 207, 191, 175, 159, 143, 128}; // Cloud Values
int clearDays[12] = {15, 12, 20, 23, 28, 37, 43, 48, 51, 41, 29, 23};
int cloudyDays[12] = {60, 61, 62, 60, 64, 63, 68, 66, 63, 54, 52, 53}; 

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
#define MAX_WAYPOINTS 200
_waypoint todaysCurve[MAX_WAYPOINTS];  // White light value at waypoint
byte todaysCurveSize;        // how many waypoints the day will have

// Starting time for the day's clouds (maximum of 10 for this test)
#define MAX_CLOUDS 10
int todaysClouds[MAX_CLOUDS];
byte todaysNumOfClouds;

// RTC variables
byte second, rtcMins, oldMins, rtcHrs, oldHrs, dayOfWeek, dayOfMonth, month, year, psecond; 
byte prevDayOfMonth;

/*
//I think month is from 1 to 12, so you have to do -1 for the arrays 0-11 elements
monthly_periods[month-1].start // <- this is the sunrise for the current month
monthly_periods[month-1].stop // <- this is the sunset for the current month
monthly_periods[month-1].period // <- this is the period for the current month  
*/


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

  //------------- BASIC CURVE ------------- 
  
  // for this test we'll use a simple trapezoid curve of 6 waypoints
  
  _waypoint basicDayCurve[6];
  int basicDayCurveSize = 6;

  int fadeDuration = map(aDay, 1, daysInMonth[aMonth-1], minFadeDuration[aMonth-1], maxFadeDuration[aMonth-1]);
  int sunriseStart = map(aDay, 1, daysInMonth[aMonth-1], minSunriseStart[aMonth-1], maxSunriseStart[aMonth-1]);
  int sunriseFinish = sunriseStart + fadeDuration;

  int sunsetFinish = map(aDay, 1, daysInMonth[aMonth-1], minSunriseStart[aMonth-1], maxSunriseStart[aMonth-1]);
  int sunsetStart = sunsetFinish - fadeDuration;
  
  basicDayCurve[0].time = 0;
  basicDayCurve[0].level = 0;
  
  basicDayCurve[1].time = sunriseStart;
  basicDayCurve[1].level = 0;
  
  basicDayCurve[2].time = sunriseFinish;
  basicDayCurve[2].level = whiteMax;
  
  basicDayCurve[3].time = sunsetStart;
  basicDayCurve[3].level = whiteMax;
  
  basicDayCurve[4].time = sunsetFinish;
  basicDayCurve[4].level = 0;
  
  basicDayCurve[5].time = 1440;
  basicDayCurve[5].level = 0;
  
  //------------- CLOUDS  ------------- 

  // In future versions the clouds section should determine from weather
  // data now many clouds to expect for the day, then calculate them
  // But in this version we're hard coding them just for testing purposes
  
  todaysNumOfClouds = 3;
  // Add a cloud when we are ramping up
  todaysClouds[0] = sunriseStart + 50;
  
  // Add a cloud when we are at the stable level
  todaysClouds[1] = sunriseFinish + 100;
  
  // Add a cloud slightly before we start sunsetting,
  // in order to check cloud intersection with basic curve waypoints
  todaysClouds[2] = sunsetStart - 10;
  
  //------------- BUILD TODAY'S CURVE  ------------- 
  _waypoint wp = { 0, 0 };
  _waypoint prevWp = { 0, 0 };
  int nextWpIndex = 0;
  int cloudIndex = 0;

  // Every curve starts with 0,0
  todaysCurve[0].time=0;
  todaysCurve[0].level=0;
  nextWpIndex = 1;

  // Go through the basic curve and fit the clouds into it
  for (int nextBasicWpIndex=1; nextBasicWpIndex < basicDayCurveSize; nextBasicWpIndex++) {
    _waypoint segmentStartWp;
    _waypoint segmentFinishWp;
    float segmentSlope;

    segmentStartWp = basicDayCurve[nextBasicWpIndex-1];  // Previous waypoint
    segmentFinishWp = basicDayCurve[nextBasicWpIndex];   // Next waypoint
    // Calculate the slope
    segmentSlope = calcSlope(segmentStartWp.time, segmentStartWp.level, segmentFinishWp.time, segmentFinishWp.level);

    // Does the next cloud intersect this segment?
    if (todaysClouds[cloudIndex] <= segmentFinishWp.time) {
      // Ok, there is a cloud starting before the end of this segment

      // We need to loop through the cloud, being careful to change segment
      // at the right time if the cloud continues after this segment's end
      for (int cloudShapeIndex=0; cloudShapeIndex < CLOUD_SHAPE_POINTS; cloudShapeIndex++) {
        float nextCloudWpReductionFactor;

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
          
          if (cloudShape[cloudShapeIndex + 1].time > segmentFinishWp.time) {
            // Humm, the cloud spans more than one segment....
            // .... need to move to the next segment now
            // WATCH OUT FOR END OF BASIC DAY CURVE
            nextBasicWpIndex++;
            
            segmentStartWp = segmentFinishWp;               // Previous waypoint
            segmentFinishWp = basicDayCurve[nextBasicWpIndex];   // Next waypoint
            // Calculate the slope
            segmentSlope = calcSlope(segmentStartWp.time, segmentStartWp.level, segmentFinishWp.time, segmentFinishWp.level);
          }
        }
      }

      // Prepare next cloud for loop
      if (cloudIndex < todaysNumOfClouds) {
        // Only move the cloud index forward if we still have clouds to insert into the curve
        cloudIndex++;
      }
      
    } else {
      // No cloud, just set the waypoint as the end of the segment
      todaysCurve[nextWpIndex] = basicDayCurve[nextBasicWpIndex];
      nextWpIndex++;
    }
  }
}

void dumpCurve( void ) {
  Serial.println("-----------------------------");
  Serial.print("month: ");
  Serial.print(month, DEC);
  Serial.print(", day: ");
  Serial.println(dayOfMonth, DEC);
  
  Serial.println("Index, Time, Level");
  for (int i=0; i < todaysCurveSize; i++) {
     Serial.print(i, DEC);
     Serial.print(todaysCurve[i].time, DEC);
     Serial.print(todaysCurve[i].level, DEC);
     Serial.println();
  }
  Serial.println("-----------------------------");
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

}

/*************************************
 * Main Loop
 **/
void loop() {
  delay(1000);
}

/*************************************
 * SETUP
 **/
void setup()  { 
  
  Serial.begin(9600);
  
  Serial.println("RESET VARIABLES -------------------");
  resetVariables(); 
 
  // Testing variables
  month = 1;         // February
  dayOfMonth = 4;    // Fifth day of month 
  
  Serial.println("PLAN NEW DAY ----------------------");
  planNewDay(month, dayOfMonth);

  Serial.println("DUMP CURVE ------------------------");
  dumpCurve();
  
} 


