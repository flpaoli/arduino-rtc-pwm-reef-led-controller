/**********************************************************************************
    Aquarium LED controller with weather simulation
    Copyright (C) 2010, 2011, Fabio Luis De Paoli

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License version 3 as published
    by the Free Software Foundation.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License v3
    along with this program.  If not, see 
    <http://www.gnu.org/licenses/gpl-3.0-standalone.html>.
 
**********************************************************************************/


// Set up RTC
#include "Wire.h"
#define DS1307_I2C_ADDRESS 0x68

// Definition of a light waypoint
struct _waypoint {
  unsigned int time;   // in 2 seconds, 1h=900 2secs, 24h = 43200 2secs
  byte         level;
};

// Definition of a segment
struct _segment {
  unsigned int strTime;  // Start
  byte         strLevel;  // Start
  unsigned int finTime;  // Finish
  byte         finLevel;  // Finish
};

// RTC variables
byte second, minute, oldMins, hour, oldHrs, dayOfWeek, dayOfMonth, month, year;
byte prevDayOfMonth;
unsigned int  pTimeCounter;
byte okta;
unsigned int currCloudCoverStart;
unsigned int currCloudCoverFinish;
unsigned int cloudSpacing;
byte cloudType1;
byte cloudType2;

#define WHITE_MAX 100          // Maximum white level

#define SHORT_CLOUD 0          // 5 MINUTES
#define LONG_CLOUD 1           // 20 MINUTES
#define THUNDERSTORM_CLOUD 10  // 2 HOURS
#define NO_CLOUD 255           // Special index value to inform not inside cloud

// Definition of a cloud
struct _cloud {
  unsigned int   start;
  byte           type;
};

// Maximum number of clouds defined at once, limited by Arduino memory
#define MAXCLOUDS 10
_cloud clouds[MAXCLOUDS];
byte qtyClouds = 0;       // How many clouds do we have active now in the array?

// So for January 1-15 was clear, so 16-60 was cloudy and 61-100 would be mixed. 
int clearDays[12] = {15, 12, 20, 23, 28, 37, 43, 48, 51, 41, 29, 23};    // From 0 to clearDays = clear day (oktas 0..1)
int cloudyDays[12] = {60, 61, 62, 60, 64, 63, 68, 66, 63, 54, 52, 53};   // From clearDays to cloudyDays = cloudy day (oktas 4..8)
// From cloudyDays to 100 = mixed day (oktas 2..3)


//Cloud shape curve
#define SHORT_CLOUD_POINTS 9
const _waypoint shortCloud[SHORT_CLOUD_POINTS] = {
  { 0, 0 } ,
  { 17, 30 } ,   //34 seconds deep fade
  { 31, 40 } ,   //62 seconds shallow fade
  { 60, 35 } ,   //160 seconds level
  { 80, 40 } ,   // with a small up and down zigzag
  { 100, 35 } ,   
  { 109, 40 } ,  
  { 140, 30 } ,  //62 seconds shallow fade
  { 150, 0  }    //20 seconds deep fade
  // Total time = 5min =  300secs or 150*2secs
};

//Cloud shape curve
#define LONG_CLOUD_POINTS 15
const _waypoint longCloud[LONG_CLOUD_POINTS] = {
  { 0, 0 } ,
  { 17, 30 } ,   //34 seconds deep fade
  { 31, 42 } ,   //62 seconds shallow fade
  { 60, 33 } ,   
  { 80, 41 } ,   
  { 100, 35 } ,   
  { 200, 40 } ,  
  { 250, 37 } ,   
  { 300, 43 } ,  
  { 350, 20 } ,   
  { 400, 31 } ,  
  { 450, 50 } ,   
  { 500, 32 } ,  
  { 580, 38 } ,  
  { 600, 0  }    
  // Total time = 20min =  1200secs or 600*2secs
};

//Thunderstorm cloud shape curve
#define THUNDERSTORM_SHAPE_POINTS 7
const _waypoint thunderstormCloud[THUNDERSTORM_SHAPE_POINTS] = {
  { 0, 0 } ,
  { 90, 50 } ,    //180 seconds deep fade
  { 270, 70 } ,   //360 seconds shallow fade
  { 2070, 70 } ,  //3600 seconds level (1 hour)
  { 2370, 50 } ,  
  { 3300, 60 },
  { 3600, 0  }    //600 seconds deep fade
  // total time = 7200 seconds = 3600*2secs =2 hours
};

#define BASICDAYCURVESIZE 14
_waypoint basicDayCurve[BASICDAYCURVESIZE];

// Month Data for Start, Stop, Photo Period and Fade (based off of actual times, best not to change)
//Days in each month
unsigned int daysInMonth[12] = {
  31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};  

//Minimum and Maximum sunrise start times in each month
unsigned int minSunriseStart[12] = {
  296, 321, 340, 357, 372, 389, 398, 389, 361, 327, 297, 285}; 
unsigned int maxSunriseStart[12] = {
  320, 340, 356, 372, 389, 398, 389, 361, 327, 297, 285, 296}; 

//Minimum and Maximum sunset stop times each month
unsigned int minSunsetFinish[12] = {
  1126, 1122, 1101, 1068, 1038, 1022, 1025, 1039, 1054, 1068, 1085, 1108}; 
unsigned int maxSunsetFinish[12] = {
  1122, 1101, 1068, 1038, 1022, 1025, 1039, 1054, 1068, 1085, 1108, 1126}; 

//Minimum and Maximum sunrise or sunset fade duration in each month
unsigned int minFadeDuration[12] = {
  350, 342, 321, 291, 226, 173, 146, 110, 122, 139, 217, 282}; 
unsigned int maxFadeDuration[12] = {
  342, 321, 291, 226, 173, 146, 110, 122, 139, 217, 282, 350}; 


/******************************************************************************************
 * DUMP CLOUDS
 *
 * Print out to the serial port the current cloud batch
 **/
void dumpClouds( void ) {
  Serial.println("DUMP CLOUDS =========================");

  Serial.println("Index, Time, type / duration");
  for (int i=0; i < qtyClouds; i++) {
    Serial.print(i, DEC);
    Serial.print(", ");
    Serial.print(clouds[i].start, DEC);
    Serial.print(", ");
    Serial.print(clouds[i].type, DEC);
    Serial.print(" / ");
    Serial.print(getCloudDuration(clouds[i].type), DEC);
    Serial.println();
  }
  Serial.println("  =========================");
}


/******************************************************************************************
 * BCD TO DEC
 *
 * Convert binary coded decimal to normal decimal
 * numbers
 **/
byte bcdToDec(byte val)
{
  return ( (val/16*10) + (val%16) );
}

/******************************************************************************************
 * GET DATE DS1307
 *
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
  Wire.send(0x00);
  Wire.endTransmission();

  Wire.requestFrom(DS1307_I2C_ADDRESS, 7);

  *second     = bcdToDec(Wire.receive() & 0x7f);
  *minute     = bcdToDec(Wire.receive());
  *hour       = bcdToDec(Wire.receive() & 0x3f);
  *dayOfWeek  = bcdToDec(Wire.receive());
  *dayOfMonth = bcdToDec(Wire.receive());
  *month      = bcdToDec(Wire.receive());
  *year       = bcdToDec(Wire.receive());
  
  Serial.print(*hour, DEC);
  Serial.print(":");
  Serial.print(*minute, DEC);
  Serial.print(":");
  Serial.print(*second, DEC);
  Serial.print("  ");
  Serial.print(*year, DEC);
  Serial.print("-");
  Serial.print(*month, DEC);
  Serial.print("-");
  Serial.print(*dayOfMonth, DEC);
  Serial.print(" @");
  Serial.print(*dayOfWeek, DEC);

}

/******************************************************************************************
 * DUMP CURVE
 *
 * Print out to the serial port today's basicDayCurve
 **/
void dumpCurve( void ) {
  Serial.println("DUMP CURVE ------------------------");
  Serial.print("month: ");
  Serial.print(month, DEC);
  Serial.print(", day: ");
  Serial.println(dayOfMonth, DEC);

  Serial.println("Index, Time, Level");
  for (int i=0; i < BASICDAYCURVESIZE; i++) {
    Serial.print(i, DEC);
    Serial.print(", ");
    Serial.print(basicDayCurve[i].time, DEC);
    Serial.print(", ");
    Serial.print(basicDayCurve[i].level, DEC);
    Serial.println();
  }
  Serial.println("-----------------------------");
}

/**************************************************************************
 * GET CLOUD DURATION
 *
 * Informs how long a cloud is.  In future versions this should be dynamic
 * permitting random cloud sizes.
 **/
unsigned int getCloudDuration(byte type) {
  switch (type) {
    case SHORT_CLOUD:         return shortCloud[SHORT_CLOUD_POINTS-1].time;
    case LONG_CLOUD:          return longCloud[LONG_CLOUD_POINTS-1].time;
    case THUNDERSTORM_CLOUD:  return thunderstormCloud[THUNDERSTORM_SHAPE_POINTS-1].time;
    default: return 0;
  }
}

/**************************************************************************
 * GET CLOUD SEGMENT
 *
 * Sets the start and finish time and level variables with the waypoints of the CLOUD
 * segment corresponding to the indexed cloud and cloud segment
 **/
void getCloudSegment(byte cloudIndex, byte cloudSegIndex, unsigned int *strTime, byte *strLevel, unsigned int *finTime, byte *finLevel) {
  unsigned int clSegStrTime;
  long         clSegStrLevel;
  unsigned int clSegFinTime;
  long         clSegFinLevel;
  _segment     clSegStrSeg;
  _segment     clSegFinSeg;
  
  switch (clouds[cloudIndex].type) {
    case SHORT_CLOUD:         
      clSegStrTime = shortCloud[cloudSegIndex].time + clouds[cloudIndex].start;
      clSegFinTime = shortCloud[cloudSegIndex + 1].time + clouds[cloudIndex].start;
      break;

    case LONG_CLOUD:      
      clSegStrTime = longCloud[cloudSegIndex].time + clouds[cloudIndex].start;
      clSegFinTime = longCloud[cloudSegIndex + 1].time + clouds[cloudIndex].start;
      break;    

    case THUNDERSTORM_CLOUD:  
      clSegStrTime = thunderstormCloud[cloudSegIndex].time + clouds[cloudIndex].start;
      clSegFinTime = thunderstormCloud[cloudSegIndex + 1].time + clouds[cloudIndex].start;
      break;    

    default: return;    // ERROR!!!  
  }

  // Get the segments of the cloud segment start and finish waypoints
  // It is on them that we'll map to find the curve level and then apply the cloud reduction factor
  getSegment(clSegStrTime, &clSegStrSeg.strTime, &clSegStrSeg.strLevel, &clSegStrSeg.finTime, &clSegStrSeg.finLevel);
  getSegment(clSegFinTime, &clSegFinSeg.strTime, &clSegFinSeg.strLevel, &clSegFinSeg.finTime, &clSegFinSeg.finLevel);
  
  // Map to find original level, then apply reductors
  clSegStrLevel = map((long) clSegStrTime, (long) clSegStrSeg.strTime, (long) clSegStrSeg.finTime, (long) clSegStrSeg.strLevel, (long) clSegStrSeg.finLevel);
  clSegFinLevel = map((long) clSegFinTime, (long) clSegFinSeg.strTime, (long) clSegFinSeg.finTime, (long) clSegFinSeg.strLevel, (long) clSegFinSeg.finLevel);

  switch (clouds[cloudIndex].type) {
    case SHORT_CLOUD:         
      clSegStrLevel = (clSegStrLevel * (100L - (long) shortCloud[cloudSegIndex].level)/100L);
      clSegFinLevel = (clSegFinLevel * (100L - (long) shortCloud[cloudSegIndex+1].level)/100L);
      break;

    case LONG_CLOUD:      
      clSegStrLevel = (clSegStrLevel * (100L - (long) longCloud[cloudSegIndex].level)/100L);
      clSegFinLevel = (clSegFinLevel * (100L - (long) longCloud[cloudSegIndex+1].level)/100L);
      break;    

    case THUNDERSTORM_CLOUD:  
      clSegStrLevel = (clSegStrLevel * (100L - (long) thunderstormCloud[cloudSegIndex].level)/100L);
      clSegFinLevel = (clSegFinLevel * (100L - (long) thunderstormCloud[cloudSegIndex+1].level)/100L);
      break;    

    default: return;    // ERROR!!!  
  }

  *strTime  = clSegStrTime;
  *strLevel = (byte) clSegStrLevel;
  *finTime  = clSegFinTime;
  *finLevel = (byte) clSegFinLevel;
}

/**************************************************************************
 * GET LEVEL
 *
 * Returns the expected level for a given moment in time
 * and informs if inside a thunderstorm (may be used for 
 * lightning production)
 **/
byte getLevel(unsigned int now, boolean *inThunderstorm) {
  byte result;
  byte cloudIndex;
  byte cloudSegIndex;
  _segment seg;
  
  *inThunderstorm = false;
  cloudIndex = insideCloud(now);
  
  if (cloudIndex == NO_CLOUD) {
    // Not in a cloud, just map the position to the basic day curve
    getSegment(now, &seg.strTime, &seg.strLevel, &seg.finTime, &seg.finLevel);
    result = map(now, seg.strTime, seg.finTime, seg.strLevel, seg.finLevel);
    
  } else {
    // OK, we're in a cloud....
    // Get first cloud segment
    cloudSegIndex = 0;
    getCloudSegment(cloudIndex, cloudSegIndex, &seg.strTime, &seg.strLevel, &seg.finTime, &seg.finLevel);
//    Serial.print("Now:");
//    Serial.print(now,DEC);
//    Serial.print(" C:");
//    Serial.print(cloudIndex,DEC);
//    Serial.print(" S:");
//    Serial.print(cloudSegIndex,DEC);
//    Serial.print(" sT:");
//    Serial.print(seg.strTime,DEC);
//    Serial.print(" fT:");
//    Serial.print(seg.finTime,DEC);
//    Serial.print(" sL:");
//    Serial.print(seg.strLevel,DEC);
//    Serial.print(" fL:");
//    Serial.print(seg.finLevel,DEC);
//    Serial.println();
    
    while (seg.finTime < now) {
      // now isn't in this cloud segment, so get the next one and check
      cloudSegIndex++;
      getCloudSegment(cloudIndex, cloudSegIndex, &seg.strTime, &seg.strLevel, &seg.finTime, &seg.finLevel);
//      Serial.print("Now:");
//      Serial.print(now,DEC);
//      Serial.print(" C:");
//      Serial.print(cloudIndex,DEC);
//      Serial.print(" S:");
//      Serial.print(cloudSegIndex,DEC);
//      Serial.print(" sT:");
//      Serial.print(seg.strTime,DEC);
//      Serial.print(" fT:");
//      Serial.print(seg.finTime,DEC);
//      Serial.print(" sL:");
//      Serial.print(seg.strLevel,DEC);
//      Serial.print(" fL:");
//      Serial.print(seg.finLevel,DEC);
//      Serial.println();
    }
    
    // found the cloud segment that now is inside, map the level
    result = map(now, seg.strTime, seg.finTime, seg.strLevel, seg.finLevel);
    
    // Inform if we're in a thunderstorm cloud
    if (clouds[cloudIndex].type == THUNDERSTORM_CLOUD) {
      *inThunderstorm = true;
    }
  }
  
  return result;
}
  

  
/**************************************************************************
 * GET SEGMENT
 *
 * Sets the start andfinish time and level variables with the waypoints of the segment
 * in which the time "when" is contained inside
 **/
void getSegment(int when, unsigned int *strTime, byte *strLevel, unsigned int *finTime, byte *finLevel) {
  
  int index = 0;
  for (int i=1; i < BASICDAYCURVESIZE ; i++ ) {
    if (when < basicDayCurve[i].time) {
      index = i-1;
      i=BASICDAYCURVESIZE;
    }
  }
  
  *strTime = basicDayCurve[index].time;
  *strLevel = basicDayCurve[index].level;
  *finTime = basicDayCurve[index+1].time;
  *finLevel = basicDayCurve[index+1].level;

}

/**************************************************************************
 * INSIDE CLOUD
 *
 * Returns the index of a cloud if the moment in time is inside a cloud
 * or the constant NO_CLOUD if not
 **/
byte insideCloud (unsigned int now) {

  // if it is still before the first cloud, exit
  if (now <= clouds[0].start) {
    return NO_CLOUD;
  }
  
  // First see which clouds starts before now
  byte cloudIndex = NO_CLOUD;

  // Loop through the clouds only if now isn't greater than the start of the last cloud
  if (now < clouds[qtyClouds-1].start) {  
    for (int c=1; c < qtyClouds; c++){
      if (now < clouds[c].start) {
        cloudIndex = c-1;
        c=qtyClouds;      // break the loop
      }
    }
  } else {
    // index set to the last cloud, for now is after it's start
    cloudIndex = (qtyClouds-1);
  }
 
  // Then, if there is one starting right before now, check to see if 
  // ir ends after now
  if (cloudIndex != NO_CLOUD) {
    if ((clouds[cloudIndex].start + getCloudDuration(clouds[cloudIndex].type)) <= now ) {
      // Not inside that cloud....
      cloudIndex = NO_CLOUD;
    }
  }

  return cloudIndex;
}

/**************************************************************************
 * PLAN BASIC CURVE
 *
 * Plan the basic light curve for the day, before clouds and other
 * special effects are considered, just sunrise/sunset and the rest.
 **/
void planBasicCurve(byte aMonth, byte aDay) {

  unsigned int sunriseStart;
  unsigned int sunsetFinish;
  unsigned int fadeDuration;
  unsigned int fadeStep;
  
  //------------- BASIC CURVE ------------- 
  fadeDuration = (unsigned int) map((long) aDay, 1L, (long) daysInMonth[aMonth-1], (long) minFadeDuration[aMonth-1], (long) maxFadeDuration[aMonth-1]);
  sunriseStart = (unsigned int) map((long) aDay, 1L, (long) daysInMonth[aMonth-1], (long) minSunriseStart[aMonth-1], (long) maxSunriseStart[aMonth-1]);
  sunsetFinish = (unsigned int) map((long) aDay, 1L, (long) daysInMonth[aMonth-1], (long) minSunsetFinish[aMonth-1], (long) maxSunsetFinish[aMonth-1]);

  // 30 transoforms "1 min" in "2 secs":
  fadeDuration = fadeDuration * 30;
  sunriseStart = sunriseStart * 30;
  sunsetFinish = sunsetFinish * 30;
  fadeStep = fadeDuration / 5;


  basicDayCurve[0].time = 0;
  basicDayCurve[0].level = 0;

  basicDayCurve[1].time = sunriseStart;  
  basicDayCurve[1].level = 0;

  basicDayCurve[2].time = sunriseStart + fadeStep;
  basicDayCurve[2].level = (WHITE_MAX * 10) / 100;

  basicDayCurve[3].time = sunriseStart + 2*fadeStep;
  basicDayCurve[3].level = (WHITE_MAX * 30) / 100;

  basicDayCurve[4].time = sunriseStart + 3*fadeStep;
  basicDayCurve[4].level = (WHITE_MAX * 70) / 100;

  basicDayCurve[5].time = sunriseStart + 4*fadeStep;
  basicDayCurve[5].level = (WHITE_MAX * 90) / 100;

  basicDayCurve[6].time = sunriseStart + 5*fadeStep;
  basicDayCurve[6].level = WHITE_MAX;

  basicDayCurve[7].time = sunsetFinish - 5*fadeStep;
  basicDayCurve[7].level = WHITE_MAX;

  basicDayCurve[8].time = sunsetFinish - 4*fadeStep;
  basicDayCurve[8].level = (WHITE_MAX * 90) / 100;

  basicDayCurve[9].time = sunsetFinish - 3*fadeStep;
  basicDayCurve[9].level = (WHITE_MAX * 70) / 100;

  basicDayCurve[10].time = sunsetFinish - 2*fadeStep;
  basicDayCurve[10].level = (WHITE_MAX * 30) / 100;

  basicDayCurve[11].time = sunsetFinish - fadeStep;
  basicDayCurve[11].level = (WHITE_MAX * 10) / 100;

  basicDayCurve[12].time = sunsetFinish;
  basicDayCurve[12].level = 0;

  basicDayCurve[13].time = 1440 * 30;
  basicDayCurve[13].level = 0;
}

/**************************************************************************
 * PLAN NEW DAY
 *
 * This is the function that is called when we enter a new day, it calls
 * planBasicCurve for the basic light with no clouds, then determines
 * the oktas number for the day, which will determine how many clouds
 * and at what spacing we will have 
 **/
void planNewDay(byte aMonth, byte aDay) {

  planBasicCurve(aMonth, aDay);
  
  //------------- OKTA DETERMINATION  ------------- 

  long randNumber;
  randNumber = random(0,100);

  if (randNumber > cloudyDays[aMonth]) {
    // this is a mixed day, Okta 2 to 3
    okta = (byte) random(2,4);
    Serial.print("Mixed day, okta=");
    Serial.print(okta, DEC);

  } else if (randNumber > clearDays[aMonth] ) {
    // this is a cloudy day, Okta 4 to 8
    okta = (byte) random(4,9);

    Serial.print("Cloudy day, okta=");
    Serial.print(okta, DEC);

  } else {
    // this is a clear day, Okta 0 to 1
    okta = (byte) random(0,2);
    Serial.print("Clear day, okta=");
    Serial.print(okta, DEC);
  }

  setCloudSpacingAndTypes();

  Serial.print(", Cloud spacing=");
  Serial.print(cloudSpacing, DEC);
  Serial.print(", Cloud type1=");
  Serial.print(cloudType1, DEC);
  Serial.print(", Cloud type2=");
  Serial.println(cloudType2, DEC);


}

/**************************************************************************
 * SET CLOUD SPACING AND TYPES
 *
 * This function is separate just to permit xUnit testing of it.  It is
 * an integral part of planNewDay.  Based on okta number determine type
 * and spacing of clouds
 **/
void setCloudSpacingAndTypes()
{
    switch (okta) {
    case 0:
      // No clouds, nothing to do....
      cloudSpacing = 0;
      break;
      
    case 1:
    case 2: // these days will be "short cloud + space"
      cloudSpacing=(8-okta) * getCloudDuration(SHORT_CLOUD);
      cloudType1=SHORT_CLOUD;
      cloudType2=SHORT_CLOUD;
      break;
      
    case 3:
    case 4: // these days will be "short cloud + space + long cloud + space"
      cloudSpacing=(8-okta) * getCloudDuration(SHORT_CLOUD);
      cloudType1=SHORT_CLOUD;
      cloudType2=LONG_CLOUD;
      break;
      
    case 5: // Morning of short clouds spaced as an okta 2 day, followed by one thunderstorm in the afternoon;
      cloudSpacing=6 * getCloudDuration(SHORT_CLOUD);
      cloudType1=SHORT_CLOUD;
      cloudType2=SHORT_CLOUD;
      break;
      
    case 6: // Morning of long clouds spaced as an okta 4 day, followed by one thunderstorm in the afternoon;
      cloudSpacing=4 * getCloudDuration(SHORT_CLOUD);
      cloudType1=LONG_CLOUD;
      cloudType2=LONG_CLOUD;
      break;
      
    case 7: // these days will be "long cloud + space"
      cloudSpacing=2 * getCloudDuration(SHORT_CLOUD);
      cloudType1=LONG_CLOUD;
      cloudType2=LONG_CLOUD;
      break;
        
    case 8: // heavy thunderstorm day... one after the other with a short space between them
      cloudSpacing=getCloudDuration(SHORT_CLOUD);
      cloudType1=THUNDERSTORM_CLOUD;
      cloudType2=THUNDERSTORM_CLOUD;
      break;
    
    default:
      cloudSpacing=0;
      break;
  }
  
}


/**************************************************************************
 * PLAN NEXT CLOUD BATCH
 *
 * In order to save Arduino's limited memory we don't plan all the days 
 * clouds at once, but rather in batches of 10.  This function must be
 * called when the previous batch has ended and it is time to plan
 * the next.  If this is called before the current cloud cover finishes
 * it exits doing nothing.
 **/
void planNextCloudBatch(unsigned int now) {

  if (now <= currCloudCoverFinish) {
    // too soon, do nothing
    //Serial.print("now ");
    //Serial.print(now, DEC);
    //Serial.print(" <= ");
    //Serial.print(currCloudCoverFinish, DEC);
    //Serial.print(" currCloudCoverFinish");
    //Serial.println();
    return;
  } 
  
  if (okta == 0) {
    // No clouds today
    currCloudCoverStart=0;
    currCloudCoverFinish=1440*30;
    qtyClouds=0;    
    return;
  }

  // Space the next cloud batch from the last onw
  currCloudCoverStart = currCloudCoverFinish + cloudSpacing;
  
  //Serial.print("now=");
  //Serial.print(now, DEC);
  //Serial.print(", okta=");
  //Serial.print(okta, DEC);
  //Serial.println();

  if ( (now > (1440L*30L/2L)) && ((okta == 5) || (okta == 6))) {
    //Serial.println("Special days as afternoon is different from morning");
    // These are special days as afternoon is different from morning
    qtyClouds = 1;
    // Start the thunderstorm from one to two hours after midday
    clouds[0].start = (1440L*30L/2L) + (unsigned int) random(0L, 120L*30L);
    clouds[0].type = THUNDERSTORM_CLOUD;
    
    // Set cloud finish to end of day, to ensure we only get one thunderstorm
    currCloudCoverFinish = 1440L*30L;
      
  } else {
    unsigned int timePos = currCloudCoverStart;
    unsigned int cloudCount = 0;

    for (int i=0; i<(MAXCLOUDS/2); i++) {
      
      if ( (timePos > (1440L*30L/2L)) && ((okta == 5) || (okta == 6))) {
        i=MAXCLOUDS;
        // Stop the loop if this is an afternoon thunderstorm day
        // and we're past midday
        
      } else {

        clouds[i*2].start    = timePos;
        clouds[i*2].type     = cloudType1;
        
        timePos = timePos + getCloudDuration(cloudType1) + cloudSpacing;
              
        clouds[i*2 + 1].start  = timePos;
        clouds[i*2 + 1].type   = cloudType2;
        
        timePos = timePos + getCloudDuration(cloudType2) + cloudSpacing;
        cloudCount = cloudCount+2;
      }
    }
    qtyClouds            = cloudCount;
    currCloudCoverFinish = timePos;
  }
  
}


/**************************************************************************
 * LOOP
 *
 **/
void loop() {
  // put your main code here, to run repeatedly: 
  
}

/**************************************************************************
 * SETUP
 *
 **/
void setup() {
  // put your setup code here, to run once:
  Wire.begin();
  Serial.begin(9600);
  
//  Serial.println("UNIT TESTING START ##########################");
//  xUnitTests();
//  Serial.println("UNIT TESTING FINISH #########################");
  
  Serial.println("getDateDs1307 ##########################");
  getDateDs1307(&second, &minute, &hour, &dayOfWeek, &dayOfMonth, &month, &year);
  
  Serial.println("randomSeed ##########################");
  randomSeed(dayOfMonth * second * year);
  
  // Zero the key variables
  currCloudCoverStart  = 0;
  currCloudCoverFinish = 0;
  month = 1;
  dayOfMonth = 1;
  
  Serial.println("planNewDay ##########################");
  planNewDay(month, dayOfMonth);
  
  dumpCurve();

  Serial.println("xTestRun ##########################");
  xTestRun();

}



//****************************************************************************************************************************************************
// Test Run
void xTestRun() {
  unsigned int tNow;
  byte tLevel;
  byte tPrevLevel;
  byte tInCloud;
  boolean tInThunder;

  tNow = 0L;
  tLevel = 0;
  tPrevLevel = 0;  
  tInCloud = NO_CLOUD;
  tInThunder = false;

  logLevel(tNow, tLevel, tInCloud, tInThunder);
  
  for (tNow=0L; tNow<43200L; tNow++) {
    tPrevLevel=tLevel;
    tLevel = getLevel(tNow, &tInThunder);
    tInCloud = insideCloud(tNow);
    if (tLevel != tPrevLevel) {
      logLevel(tNow, tLevel, tInCloud, tInThunder);
    }

    planNextCloudBatch(tNow);
  }
}

void logLevel(unsigned int tNow, byte tLevel, byte tInCloud, boolean tInThunder) 
{
  Serial.print(tNow,DEC);
  Serial.print(",");
  Serial.print(tLevel,DEC);
  Serial.print(",");
  Serial.print(tInCloud,DEC);
  Serial.print(",");
  Serial.print(tInThunder,DEC);
  Serial.println();
}

/*************************************************************************
// XUNIT TESTS OF FUNCTIONS 
//
// Test Driven Development, saves me a lot of time in debugging changes....
//
void xUnitTests() {
  
  // Setup
  
  basicDayCurve[0].time= 0;
  basicDayCurve[0].level= 0;
  basicDayCurve[1].time= 300*30;
  basicDayCurve[1].level= 10;
  basicDayCurve[2].time= 500*30;
  basicDayCurve[2].level= 90;
  basicDayCurve[3].time= 800*30;
  basicDayCurve[3].level= 95;
  basicDayCurve[4].time= 1000*30;
  basicDayCurve[4].level= 100;
  basicDayCurve[5].time= 1100*30;
  basicDayCurve[5].level= 10;
  basicDayCurve[6].time= 43200;
  basicDayCurve[6].level= 0;

  qtyClouds= 3;
  clouds[0].start=600*30;
  clouds[0].type= LONG_CLOUD;
  clouds[1].start=998*30;
  clouds[1].type= SHORT_CLOUD;
  clouds[2].start=1050*30;
  clouds[2].type= THUNDERSTORM_CLOUD;
  

  // Tests
  
  // ------------- GET SEGMENT
  _segment aSeg;

  getSegment(100*30, &aSeg.strTime, &aSeg.strLevel, &aSeg.finTime, &aSeg.finLevel);
  if (aSeg.strTime != 0) {
   Serial.println("Failed getSegment 100 str time");
  }
  if (aSeg.strLevel != 0) {
   Serial.println("Failed getSegment 100 str level");
  }
  if (aSeg.finTime != 300*30) {
   Serial.println("Failed getSegment 100 fin time");
  }
  if (aSeg.finLevel != 10) {
   Serial.println("Failed getSegment 100 fin level");
  }
  
  
  getSegment(900*30, &aSeg.strTime, &aSeg.strLevel, &aSeg.finTime, &aSeg.finLevel);
  if (aSeg.strTime != 800*30) {
   Serial.println("Failed getSegment 900 str time");
  }
  if (aSeg.strLevel != 95) {
   Serial.println("Failed getSegment 900 str level");
  }
  if (aSeg.finTime != 1000*30) {
   Serial.println("Failed getSegment 900 fin time");
  }
  if (aSeg.finLevel != 100) {
   Serial.println("Failed getSegment 900 fin level");
  }
  
  // ------------- INSIDE CLOUD
  byte cloudIndex;

  cloudIndex = insideCloud(550*30);
  if (cloudIndex != NO_CLOUD) {
   Serial.print("Failed insideCloud 550 NO_CLOUD: ");
   Serial.println(cloudIndex, DEC);
  }
    
  cloudIndex = insideCloud(601*30);
  if (cloudIndex != 0) {
   Serial.print("Failed insideCloud 601 index 0: ");
   Serial.println(cloudIndex, DEC);
  }
  
  cloudIndex = insideCloud(997*30);
  if (cloudIndex != NO_CLOUD) {
   Serial.print("Failed insideCloud 997 index NO_CLOUD: ");
   Serial.println(cloudIndex, DEC);
  }
  
  cloudIndex = insideCloud(998*30);
  if (cloudIndex != 1) {
   Serial.print("Failed insideCloud 998 index 1: ");
   Serial.println(cloudIndex, DEC);
  }
  
  cloudIndex = insideCloud(1100*30);
  if (cloudIndex != 2) {
   Serial.print("Failed insideCloud 1100 index 2: ");
   Serial.println(cloudIndex, DEC);
  }
  
  // ------------- GET CLOUD SEGMENT

  _segment  cloudSeg;
  byte      cloudSegIndex;
  byte      correctLevel;
  
  //LONG CLOUD segment 5
  //{ 100, 35 } ,   
  //{ 200, 40 } ,  
  cloudIndex = 0;
  cloudSegIndex = 5;
  getCloudSegment(cloudIndex, cloudSegIndex, &cloudSeg.strTime, &cloudSeg.strLevel, &cloudSeg.finTime, &cloudSeg.finLevel);

  assertCloudSegTime(cloudIndex, cloudSegIndex, cloudSeg.strTime, 600*30 + 100); 
  correctLevel = (map(600*30+100,500*30,800*30,90,95) * (100-35)) / 100;
  assertCloudSegLevel(cloudIndex, cloudSegIndex, cloudSeg.strLevel, correctLevel);

  assertCloudSegTime(cloudIndex, cloudSegIndex, cloudSeg.finTime, 600*30 + 200); 
  correctLevel = (map(600*30+200,500*30,800*30,90,95) * (100-40)) / 100;
  assertCloudSegLevel(cloudIndex, cloudSegIndex, cloudSeg.finLevel, correctLevel);
  
  // segment 13
  //{ 580, 38 } ,  
  //{ 600, 0  }    
  cloudSegIndex = 13;
  getCloudSegment(cloudIndex, cloudSegIndex, &cloudSeg.strTime, &cloudSeg.strLevel, &cloudSeg.finTime, &cloudSeg.finLevel);
  
  assertCloudSegTime(cloudIndex, cloudSegIndex, cloudSeg.strTime, 600*30+580); 
  correctLevel = (map(600*30+580,500*30,800*30,90,95) * (100-38)) / 100;
  assertCloudSegLevel(cloudIndex, cloudSegIndex, cloudSeg.strLevel, correctLevel);

  assertCloudSegTime(cloudIndex, cloudSegIndex, cloudSeg.finTime, 600*30 + 600); 
  correctLevel = (map(600*30+600,500*30,800*30,90,95) * (100-0)) / 100;
  assertCloudSegLevel(cloudIndex, cloudSegIndex, cloudSeg.finLevel, correctLevel);
  
  // SHORT CLOUD
  // Starts at 998*30

  // Test cloud 1 segment 0
  //{ 0, 0 } ,
  //{ 17, 30 } ,
  cloudIndex = 1;
  cloudSegIndex = 0;
  getCloudSegment(cloudIndex, cloudSegIndex, &cloudSeg.strTime, &cloudSeg.strLevel, &cloudSeg.finTime, &cloudSeg.finLevel);

  assertCloudSegTime(cloudIndex, cloudSegIndex, cloudSeg.strTime, 998*30 + 0); 
  correctLevel = (map(998*30+0,800*30,1000*30,95,100) * (100-0)) / 100;
  assertCloudSegLevel(cloudIndex, cloudSegIndex, cloudSeg.strLevel, correctLevel);

  assertCloudSegTime(cloudIndex, cloudSegIndex, cloudSeg.finTime, 998*30 + 17); 
  correctLevel = (map(998*30+17,800*30,1000*30,95,100) * (100-30)) / 100;
  assertCloudSegLevel(cloudIndex, cloudSegIndex, cloudSeg.finLevel, correctLevel);
  
  // Test cloud 1 segment 3
  //{ 60, 35 } ,
  //{ 80, 40 } ,
  cloudSegIndex = 3;
  getCloudSegment(cloudIndex, cloudSegIndex, &cloudSeg.strTime, &cloudSeg.strLevel, &cloudSeg.finTime, &cloudSeg.finLevel);

  assertCloudSegTime(cloudIndex, cloudSegIndex, cloudSeg.strTime, 998*30 + 60); 
  correctLevel = (map(998*30+60,800*30,1000*30,95,100) * (100-35)) / 100;
  assertCloudSegLevel(cloudIndex, cloudSegIndex, cloudSeg.strLevel, correctLevel);

  assertCloudSegTime(cloudIndex, cloudSegIndex, cloudSeg.finTime, 998*30 + 80); 
  correctLevel = (map(998*30+80,800*30,1000*30,95,100) * (100-40)) / 100;
  assertCloudSegLevel(cloudIndex, cloudSegIndex, cloudSeg.finLevel, correctLevel);

  // THUNDERSTORM CLOUD
  // Starts at 1050*30

  // Test cloud 2 segment 2
  //{ 270, 70 } ,   //360 seconds shallow fade
  //{ 2070, 70 } ,  //3600 seconds level (1 hour)
  cloudIndex = 2;
  cloudSegIndex = 2;
  getCloudSegment(cloudIndex, cloudSegIndex, &cloudSeg.strTime, &cloudSeg.strLevel, &cloudSeg.finTime, &cloudSeg.finLevel);

  assertCloudSegTime(cloudIndex, cloudSegIndex, cloudSeg.strTime, 1050*30+270); 
  correctLevel = (byte) ((map(1050L*30L+270L,1000L*30L,1100L*30L,100L,10L) * (100L-70L)) / 100L);
  assertCloudSegLevel(cloudIndex, cloudSegIndex, cloudSeg.strLevel, correctLevel);

  assertCloudSegTime(cloudIndex, cloudSegIndex, cloudSeg.finTime, 1050*30+2070); 
  correctLevel = (byte) ((map(1050L*30L+2070L,1100L*30L,43200L,10L,0L) * (100L-70L)) / 100L);
  assertCloudSegLevel(cloudIndex, cloudSegIndex, cloudSeg.finLevel, correctLevel);
  
  // Test cloud 2 segment 4
  //{ 2370, 50 } ,  
  //{ 3300, 60 },
  cloudSegIndex = 4;
  getCloudSegment(cloudIndex, cloudSegIndex, &cloudSeg.strTime, &cloudSeg.strLevel, &cloudSeg.finTime, &cloudSeg.finLevel);

  assertCloudSegTime(cloudIndex, cloudSegIndex, cloudSeg.strTime, 1050*30+2370); 
  correctLevel = (byte) ((map(1050L*30L+2370L,1100L*30L,43200L,10L,0L) * (100L-50L)) / 100L);
  assertCloudSegLevel(cloudIndex, cloudSegIndex, cloudSeg.strLevel, correctLevel);

  assertCloudSegTime(cloudIndex, cloudSegIndex, cloudSeg.finTime, 1050*30+3300); 
  correctLevel = (byte) ((map(1050L*30L+3300L,1100L*30L,43200L,10L,0L) * (100L-60L)) / 100L);
  assertCloudSegLevel(cloudIndex, cloudSegIndex, cloudSeg.finLevel, correctLevel);

  // ------------- GET LEVEL
  
  unsigned int tm;
  long basicLevel;
  long reductor;
  
  assertGetLevel(400*30,  10 + 100*80/200);
  assertGetLevel(500*30,  90);
  assertGetLevel(600*30,  90 + 100*5/300);

  tm = 600*30 + 100;
  basicLevel = map((long)tm,500L*30L,800L*30L,90L,95L);
  reductor = 35;
  assertGetLevel(tm, (byte) (basicLevel * (100L - reductor)/100L));

  assertGetLevel(850*30,  95 + (50*5)/200);

  tm = 1000*30;
  basicLevel = 100;
  reductor = map(60L, 31L, 60L, 40L, 35L);
  assertGetLevel(tm, (byte) (basicLevel * (100L - reductor)/100L));

  tm = 1050*30 + 2100;  // 2100 of Thunderstorm starting at 1050
  basicLevel = map((long)tm, 1100L*30L, 43200L, 10L, 0L);
  reductor = map(2100L,2070L,2370L,70L,50L);
  assertGetLevel(tm, (byte) (basicLevel * (100L - reductor)/100L));

  // -------------- PLAN NEXT CLOUD BATCH
  unsigned int cloudTestStart = 0;
  unsigned int cloudTestSpacing = 0;
  currCloudCoverStart=0;
  currCloudCoverFinish=0;
  cloudSpacing=0;

  okta = 0;
  setCloudSpacingAndTypes();
  planNextCloudBatch(1200L*30L);
  assertCloudCoverPeriods(1200L*30L, okta, 0, 1440*30, 0);
    
  okta = 1;
  setCloudSpacingAndTypes();
  currCloudCoverFinish=999L;

  cloudTestStart = currCloudCoverFinish + cloudSpacing;
  cloudTestSpacing = cloudSpacing;
  planNextCloudBatch(1000L);
  assertCloudCoverPeriods(1000L, okta, 
    cloudTestStart,
    cloudTestStart + 10L*(cloudTestSpacing + getCloudDuration(SHORT_CLOUD)),
    MAXCLOUDS);
  assertCloudTypes(okta, clouds[0].type, clouds[1].type, SHORT_CLOUD, SHORT_CLOUD);
  assertCloudSpacing(okta, clouds[0].start, clouds[1].start,
    cloudTestStart, cloudTestStart + getCloudDuration(SHORT_CLOUD) + cloudTestSpacing);

  okta = 2;
  setCloudSpacingAndTypes();
  currCloudCoverFinish=999L;

  cloudTestStart = currCloudCoverFinish + cloudSpacing;
  cloudTestSpacing = cloudSpacing;
  planNextCloudBatch(1000L);
  assertCloudCoverPeriods(1000L, okta, 
    cloudTestStart,
    cloudTestStart + 10*(cloudTestSpacing + getCloudDuration(SHORT_CLOUD)),
    MAXCLOUDS);
  assertCloudTypes(okta, clouds[0].type, clouds[1].type, SHORT_CLOUD, SHORT_CLOUD);
  assertCloudSpacing(okta, clouds[0].start, clouds[1].start,
    cloudTestStart, cloudTestStart + getCloudDuration(SHORT_CLOUD) + cloudTestSpacing);

  okta = 3;
  setCloudSpacingAndTypes();
  currCloudCoverFinish=999L;

  cloudTestStart = currCloudCoverFinish + cloudSpacing;
  cloudTestSpacing = cloudSpacing;
  planNextCloudBatch(1000L);
  assertCloudCoverPeriods(1000L, okta, 
    cloudTestStart,
    cloudTestStart + 5*(cloudTestSpacing + getCloudDuration(SHORT_CLOUD)
    + cloudTestSpacing + getCloudDuration(LONG_CLOUD)),
    MAXCLOUDS);
  assertCloudTypes(okta, clouds[0].type, clouds[1].type, SHORT_CLOUD, LONG_CLOUD);
  assertCloudSpacing(okta, clouds[0].start, clouds[1].start,
    cloudTestStart, cloudTestStart + getCloudDuration(SHORT_CLOUD) + cloudTestSpacing);
  assertCloudTypes(okta, clouds[2].type, clouds[3].type, SHORT_CLOUD, LONG_CLOUD);
  assertCloudSpacing(okta, clouds[2].start, clouds[3].start,
    cloudTestStart + getCloudDuration(SHORT_CLOUD) + cloudTestSpacing 
    + getCloudDuration(LONG_CLOUD) + cloudTestSpacing,
    cloudTestStart + getCloudDuration(SHORT_CLOUD) + cloudTestSpacing 
    + getCloudDuration(LONG_CLOUD) + cloudTestSpacing
    + getCloudDuration(SHORT_CLOUD) + cloudTestSpacing);

  okta = 4;
  setCloudSpacingAndTypes();
  currCloudCoverFinish=999L;

  cloudTestStart = currCloudCoverFinish + cloudSpacing;
  cloudTestSpacing = cloudSpacing;
  planNextCloudBatch(1000L);
  assertCloudCoverPeriods(1000L, okta, 
    cloudTestStart,
    cloudTestStart + 5*(cloudTestSpacing + getCloudDuration(SHORT_CLOUD)
    + cloudTestSpacing + getCloudDuration(LONG_CLOUD)),
    MAXCLOUDS);
  assertCloudTypes(okta, clouds[0].type, clouds[1].type, SHORT_CLOUD, LONG_CLOUD);
  assertCloudSpacing(okta, clouds[0].start, clouds[1].start,
    cloudTestStart, cloudTestStart + getCloudDuration(SHORT_CLOUD) + cloudTestSpacing);
  assertCloudTypes(okta, clouds[2].type, clouds[3].type, SHORT_CLOUD, LONG_CLOUD);
  assertCloudSpacing(okta, clouds[2].start, clouds[3].start,
    cloudTestStart + getCloudDuration(SHORT_CLOUD) + cloudTestSpacing 
    + getCloudDuration(LONG_CLOUD) + cloudTestSpacing,
    cloudTestStart + getCloudDuration(SHORT_CLOUD) + cloudTestSpacing 
    + getCloudDuration(LONG_CLOUD) + cloudTestSpacing
    + getCloudDuration(SHORT_CLOUD) + cloudTestSpacing);

  // OKTA 5
  okta = 5;
  setCloudSpacingAndTypes();

  // Okta 5 morning
  currCloudCoverFinish=100L*30L-2L;
  cloudTestStart = currCloudCoverFinish + cloudSpacing;
  cloudTestSpacing = cloudSpacing;
  planNextCloudBatch(100L*30L);
  assertCloudCoverPeriods(100L*30L, okta, 
    cloudTestStart,
    cloudTestStart + 10*(cloudTestSpacing + getCloudDuration(SHORT_CLOUD)),
    MAXCLOUDS);
  assertCloudTypes(okta, clouds[0].type, clouds[1].type, SHORT_CLOUD, SHORT_CLOUD);
  assertCloudSpacing(okta, clouds[0].start, clouds[1].start,
    cloudTestStart, cloudTestStart + getCloudDuration(SHORT_CLOUD) + cloudTestSpacing);

  // Okta 5 afternoon
  currCloudCoverFinish=800L*30L-2L;
  cloudTestStart = currCloudCoverFinish + cloudSpacing;
  cloudTestSpacing = cloudSpacing;
  planNextCloudBatch(800L*30L);
  if (qtyClouds != 1) {
    Serial.print("Failed qtyClouds afternoon okta=");
    Serial.print(okta, DEC);
    Serial.print(", testTime=");
    Serial.print(800L*30L, DEC);
    Serial.print(", qtyClouds=");
    Serial.print(qtyClouds, DEC);
    Serial.print(" not  1");
    Serial.println();
  }
  assertCloudTypes(okta, clouds[0].type, 0, THUNDERSTORM_CLOUD, 0);

  // OKTA 6
  okta = 6;
  setCloudSpacingAndTypes();

  // Okta 6 morning
  currCloudCoverFinish=100L*30L-2L;
  cloudTestStart = currCloudCoverFinish + cloudSpacing;
  cloudTestSpacing = cloudSpacing;
 
//  Serial.print("o6 currCloudCoverFinish=");
//  Serial.print(currCloudCoverFinish, DEC);
//  Serial.print(", cloudSpacing=");
//  Serial.print(cloudSpacing, DEC);
//  Serial.print(", cloudTestStart=");
//  Serial.print(cloudTestStart, DEC);
//  Serial.println();
 
  planNextCloudBatch(100L*30L);
  assertCloudCoverPeriods(100L*30L, okta, 
    cloudTestStart,
    cloudTestStart + 10*(cloudTestSpacing + getCloudDuration(LONG_CLOUD)),
    MAXCLOUDS);
  assertCloudTypes(okta, clouds[0].type, clouds[1].type, LONG_CLOUD, LONG_CLOUD);
  assertCloudSpacing(okta, clouds[0].start, clouds[1].start,
    cloudTestStart, cloudTestStart + getCloudDuration(LONG_CLOUD) + cloudTestSpacing);

  // Okta 6 afternoon
  currCloudCoverFinish=1000L*30L-2L;
  cloudTestStart = currCloudCoverFinish + cloudSpacing;
  cloudTestSpacing = cloudSpacing;
  planNextCloudBatch(1000L*30L);
  if (qtyClouds != 1) {
    Serial.print("Failed qtyClouds afternoon okta=");
    Serial.print(okta, DEC);
    Serial.print(", testTime=");
    Serial.print(1000L*30L, DEC);
    Serial.print(", qtyClouds=");
    Serial.print(qtyClouds, DEC);
    Serial.print(" not  1");
    Serial.println();
  }
  assertCloudTypes(okta, clouds[0].type, 0, THUNDERSTORM_CLOUD, 0);

  // OKTA 7
  okta = 7;
  setCloudSpacingAndTypes();
  currCloudCoverFinish=999L;

  cloudTestStart = currCloudCoverFinish + cloudSpacing;
  cloudTestSpacing = cloudSpacing;
  planNextCloudBatch(1000L);
  assertCloudCoverPeriods(1000L, okta, 
    cloudTestStart,
    cloudTestStart + 10*(cloudTestSpacing + getCloudDuration(LONG_CLOUD)),
    MAXCLOUDS);
  assertCloudTypes(okta, clouds[0].type, clouds[1].type, LONG_CLOUD, LONG_CLOUD);
  assertCloudSpacing(okta, clouds[0].start, clouds[1].start,
    cloudTestStart, cloudTestStart + getCloudDuration(LONG_CLOUD) + cloudTestSpacing);

  // OKTA 8
  okta = 8;
  setCloudSpacingAndTypes();
  currCloudCoverFinish=999L;

  cloudTestStart = currCloudCoverFinish + cloudSpacing;
  cloudTestSpacing = cloudSpacing;
  planNextCloudBatch(1000L);
  assertCloudCoverPeriods(1000L, okta, 
    cloudTestStart,
    cloudTestStart + 10*(cloudTestSpacing + getCloudDuration(THUNDERSTORM_CLOUD)),
    MAXCLOUDS);
  assertCloudTypes(okta, clouds[0].type, clouds[1].type, THUNDERSTORM_CLOUD, THUNDERSTORM_CLOUD);
  assertCloudSpacing(okta, clouds[0].start, clouds[1].start,
    cloudTestStart, cloudTestStart + getCloudDuration(THUNDERSTORM_CLOUD) + cloudTestSpacing);
    
}

void assertCloudSpacing(byte testOkta, unsigned int start1, unsigned int start2,
unsigned int refStart1, unsigned int refStart2)
{
  if (start1 != refStart1) {
    Serial.print("Failed assertCloudSpacing okta=");
    Serial.print(testOkta, DEC);
    Serial.print(", cloudStart1=");
    Serial.print(start1, DEC);
    Serial.print(" not  ");
    Serial.print(refStart1, DEC);
    Serial.println();
  }
  if (start2 != refStart2) {
    Serial.print("Failed assertCloudSpacing okta=");
    Serial.print(testOkta, DEC);
    Serial.print(", cloudStart2=");
    Serial.print(start2, DEC);
    Serial.print(" not  ");
    Serial.print(refStart2, DEC);
    Serial.println();
  }
}


void assertCloudTypes(byte testOkta, byte cloud1, byte cloud2,
byte refCloud1, byte refCloud2)
{
  if (cloud1 != refCloud1) {
    Serial.print("Failed assertCloudTypes okta=");
    Serial.print(testOkta, DEC);
    Serial.print(", cloud1=");
    Serial.print(cloud1, DEC);
    Serial.print(" not  ");
    Serial.print(refCloud1, DEC);
    Serial.println();
  }
  if (cloud2 != refCloud2) {
    Serial.print("Failed assertCloudTypes okta=");
    Serial.print(testOkta, DEC);
    Serial.print(", cloud2=");
    Serial.print(cloud2, DEC);
    Serial.print(" not  ");
    Serial.print(refCloud2, DEC);
    Serial.println();
  }
}

void assertCloudCoverPeriods(unsigned int testTime, byte testOkta, 
unsigned int coverStart, unsigned int coverFinish, byte qty)
{
  if (currCloudCoverStart != coverStart ) {
    Serial.print("Failed assertCloudCoverPeriods okta=");
    Serial.print(testOkta, DEC);
    Serial.print(", testTime=");
    Serial.print(testTime, DEC);
    Serial.print(", coverStart=");
    Serial.print(currCloudCoverStart, DEC);
    Serial.print(" not  ");
    Serial.print(coverStart, DEC);
    Serial.println();
  }
  if (currCloudCoverFinish != coverFinish) {
    Serial.print("Failed assertCloudCoverPeriods okta=");
    Serial.print(testOkta, DEC);
    Serial.print(", testTime=");
    Serial.print(testTime, DEC);
    Serial.print(", coverFinish=");
    Serial.print(currCloudCoverFinish, DEC);
    Serial.print(" not  ");
    Serial.print(coverFinish, DEC);
    Serial.println();
  }
  if (qtyClouds != qty) {
    Serial.print("Failed assertCloudCoverPeriods okta=");
    Serial.print(testOkta, DEC);
    Serial.print(", testTime=");
    Serial.print(testTime, DEC);
    Serial.print(", qtyClouds=");
    Serial.print(qtyClouds, DEC);
    Serial.print(" not  ");
    Serial.print(qty, DEC);
    Serial.println();
  }
}

void assertGetLevel(unsigned int time, byte correctLevel) {
  boolean inThunderstorm;
  byte level = getLevel(time, &inThunderstorm);
  if (level != correctLevel) {
    Serial.print("Failed getLevel at ");
    Serial.print(time, DEC);
    Serial.print(" not  ");
    Serial.print(correctLevel, DEC);
    Serial.print(" : ");
    Serial.println(level, DEC);
  }
}

void assertCloudSegTime(unsigned int cloudIndex, unsigned int cloudSegIndex, unsigned int time, unsigned int correctTime) {
  if (time != correctTime) {
   Serial.print("Failed getCloudSegment ");
   Serial.print(cloudIndex, DEC);
   Serial.print("/");
   Serial.print(cloudSegIndex, DEC);
   Serial.print(" finTime not ");
   Serial.print(correctTime, DEC);
   Serial.print(" : ");
   Serial.println(time, DEC);
  }    
}  

void assertCloudSegLevel(unsigned int cloudIndex, unsigned int cloudSegIndex, byte level, byte correctLevel) {
   if (level != correctLevel) {
     Serial.print("Failed getCloudSegment ");
     Serial.print(cloudIndex, DEC);
     Serial.print("/");
     Serial.print(cloudSegIndex, DEC);
     Serial.print(" level not ");
     Serial.print(correctLevel, DEC);
     Serial.print(" : ");
     Serial.println(level, DEC);
  }    
}
*/
