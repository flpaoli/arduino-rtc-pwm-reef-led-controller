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

  int sunsetFinish = map(aDay, 1, daysInMonth[aMonth-1], minSunsetFinish[aMonth-1], maxSunsetFinish[aMonth-1]);
  int sunsetStart = sunsetFinish - fadeDuration;

  Serial.print("sunriseStart : ");
  Serial.println(sunriseStart, DEC);
  Serial.print("sunriseFinish:");
  Serial.println(sunriseFinish, DEC);
  Serial.print("sunsetStart  : ");
  Serial.println(sunsetStart, DEC);
  Serial.print("sunsetFinish : ");
  Serial.println(sunsetFinish, DEC);
  
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

  Serial.println("Index, StartTime, StartLevel, FinishTime, FinishLevel:");

  boolean cloudStartedIntersectingSegment = false;

  // Go through the basic curve and fit the clouds into it
  for (int nextBasicWpIndex=1; nextBasicWpIndex < basicDayCurveSize; nextBasicWpIndex++) {
    _waypoint segmentStartWp;
    _waypoint segmentFinishWp;
    float segmentSlope;

    segmentStartWp = basicDayCurve[nextBasicWpIndex-1];  // Previous waypoint
    segmentFinishWp = basicDayCurve[nextBasicWpIndex];   // Next waypoint
    
    Serial.print(nextBasicWpIndex, DEC);
    Serial.print(", ");
    Serial.print(segmentStartWp.time, DEC);
    Serial.print(", ");
    Serial.print(segmentStartWp.level, DEC);
    Serial.print(", ");
    Serial.print(segmentFinishWp.time, DEC);
    Serial.print(", ");
    Serial.println(segmentFinishWp.level, DEC);
    
    // Calculate the slope
    segmentSlope = calcSlope(segmentStartWp.time, segmentStartWp.level, segmentFinishWp.time, segmentFinishWp.level);



    // Do we still have clouds to insert today?
    if (moreClouds) {
      // Does the next cloud intersect this segment?
      if (todaysClouds[cloudIndex] <= segmentFinishWp.time) {
        // Ok, there is a cloud starting before the end of this segment
        Serial.print("Starting cloud #");
        Serial.println(cloudIndex, DEC);
  
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
            Serial.println("Ok, cloud still has at least one more waypoint....");
            
            Serial.println("todaysClouds[cloudIndex] / cloudShape[cloudShapeIndex + 1].time / segmentFinishWp.time)");
            Serial.print(todaysClouds[cloudIndex], DEC);
            Serial.print(" / ");
            Serial.print(cloudShape[cloudShapeIndex + 1].time, DEC);
            Serial.print(" / ");
            Serial.println(segmentFinishWp.time, DEC);
            
            if (todaysClouds[cloudIndex] + cloudShape[cloudShapeIndex + 1].time > segmentFinishWp.time) {
              // Humm, the cloud spans more than one segment....
              // .... need to move to the next segment now
              Serial.println("---------> Humm, the cloud spans more than one segment....");
              nextBasicWpIndex++;
              
              segmentStartWp = segmentFinishWp;               // Previous waypoint
              segmentFinishWp = basicDayCurve[nextBasicWpIndex];   // Next waypoint
              // Calculate the slope
              segmentSlope = calcSlope(segmentStartWp.time, segmentStartWp.level, segmentFinishWp.time, segmentFinishWp.level);
              
              Serial.print(nextBasicWpIndex, DEC);
              Serial.print(", ");
              Serial.print(segmentStartWp.time, DEC);
              Serial.print(", ");
              Serial.print(segmentStartWp.level, DEC);
              Serial.print(", ");
              Serial.print(segmentFinishWp.time, DEC);
              Serial.print(", ");
              Serial.println(segmentFinishWp.level, DEC);
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

        Serial.println("End of cloud....");
        // End of cloud, set the next waypoint as the segment's Finish
        // But only if there is no other cloud starting before that waypoint
        // becasue if there is, it's starting point should be the next waypoint
        if (moreClouds) {
  
          Serial.println("But have more clouds...");
          // Does the next cloud intersect this segment?
          if (todaysClouds[cloudIndex] <= segmentFinishWp.time) {

            Serial.println("... and it intersects the active segment!");
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
            
            Serial.println("... but it doesn't intersect this segment, next waypoint is segment's finish");
  
            //... but it doesn't intersect this segment, next waypoint is segment's finish
            todaysCurve[nextWpIndex] = segmentFinishWp;
            nextWpIndex++;
          }

        } else {
          Serial.println("OK, no other cloud, next waypoint is segment's finish");

          // OK, no other cloud, next waypoint is segment's finish
          todaysCurve[nextWpIndex] = segmentFinishWp;
          nextWpIndex++;
        }
        
      } else {

        Serial.println("No cloud right now, just set the waypoint as the end of the segment");
        // No cloud right now, just set the waypoint as the end of the segment
        todaysCurve[nextWpIndex] = basicDayCurve[nextBasicWpIndex];
        nextWpIndex++;
      }
      
    } else {
      Serial.println("No clouds at all, just set the waypoint as the end of the segment");
      // No clouds at all, just set the waypoint as the end of the segment
      todaysCurve[nextWpIndex] = basicDayCurve[nextBasicWpIndex];
      nextWpIndex++;
    }
  }
  todaysCurveSize = nextWpIndex;
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
     Serial.print(", ");
     Serial.print(todaysCurve[i].time, DEC);
     Serial.print(", ");
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
  
  delay(1500);
  
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


