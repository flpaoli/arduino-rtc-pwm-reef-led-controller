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

#define DEBUG_MODE false
unsigned int debug_now;
byte heartbeatLevel;

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
byte second, minute, hour, dayOfWeek, dayOfMonth, month, year;
byte prevDayOfMonth;
byte prevMinute;
byte prevWLevel, prevBLevel;
byte okta;
unsigned int prevNow;
unsigned int currCloudCoverStart;
unsigned int currCloudCoverFinish;
unsigned int cloudSpacing;
byte cloudType1;
byte cloudType2;

/////////////////////////////////////////////////////////////
// Section where we define the white-blue channel pairs
struct _channelPair {
  byte wPin;
  byte bPin;
  unsigned int channelDelay;
};

#define MAX_CHANNEL_PAIRS 1
_channelPair channels[MAX_CHANNEL_PAIRS] = {
  { 10, 9, 0 }
};
////////////////////////////////////////////////////////////

#define WHITE_MAX 100          // Maximum white level
#define BLUE_MAX 100           // Maximum blue level

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
byte clearDays[12] = {15, 12, 20, 23, 28, 37, 43, 48, 51, 41, 29, 23};    // From 0 to clearDays = clear day (oktas 0..1)
byte cloudyDays[12] = {60, 61, 62, 60, 64, 63, 68, 66, 63, 54, 52, 53};   // From clearDays to cloudyDays = cloudy day (oktas 4..8)
// From cloudyDays to 100 = mixed day (oktas 2..3)

//Cloud shape curve
#define SHORT_CLOUD_POINTS 9
const _waypoint shortCloud[SHORT_CLOUD_POINTS] = {
  { 0, 0 } ,
  { 3, 20 } ,   
  { 10, 60 } ,   
  { 15, 25 } ,   
  { 20, 60 } ,   
  { 30, 35 } ,   
  { 40, 50 } ,  
  { 50, 60 } ,  
  { 60, 0  }    
  // Total time = 2min =  120secs or 60*2secs
};

//Cloud shape curve
#define LONG_CLOUD_POINTS 15
const _waypoint longCloud[LONG_CLOUD_POINTS] = {
  { 0, 0 } ,
  { 17, 60 } ,   //34 seconds deep fade
  { 31, 42 } ,   //62 seconds shallow fade
  { 60, 23 } ,   
  { 80, 51 } ,   
  { 100, 15 } ,   
  { 200, 40 } ,  
  { 250, 37 } ,   
  { 300, 53 } ,  
  { 350, 20 } ,   
  { 400, 31 } ,  
  { 450, 50 } ,   
  { 500, 32 } ,  
  { 580, 68 } ,  
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
_waypoint dcwWhiteCurve[BASICDAYCURVESIZE];
_waypoint dcwBlueCurve[BASICDAYCURVESIZE];


// Month Data for Start, Stop, Photo Period and Fade (based off of actual times, best not to change)
//Days in each month
byte daysInMonth[12] = {
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
 * BCD TO DEC
 *
 * Convert binary coded decimal to normal decimal
 * numbers
 **/
byte bcdToDec(byte val)
{
  return ( (val/16*10) + (val%16) );
}

// Convert normal decimal numbers to binary coded decimal
byte decToBcd(byte val)
{
  return ( (val/10*16) + (val%10) );
}


/******************************************************************************************
 * DO LIGHTNING
 *
 * Do lightning, flashing all the LEDs at full intensity in a lightning like pattern.
 *
 * Inspired by lightning code posted by Numlock10@ReefCentral
 * http://www.reefcentral.com/forums/showpost.php?p=17542851&postcount=206
 **/
void doLightning(byte aWhiteLevel, byte aBlueLevel) {
    byte numberOfFlashes = (byte) random(5) +1;
    byte maxLightLevel;

    if (aBlueLevel < 20) {
      maxLightLevel = (aBlueLevel * 2) + 3;
    } else {
      maxLightLevel = WHITE_MAX;
    }

    byte var = 0;
    while (var < numberOfFlashes) {
      // LEDs on for 50ms
      for (byte i=0; i<MAX_CHANNEL_PAIRS; i++) {
        setLedPWMOutputs(i, maxLightLevel, maxLightLevel);
      }
      delay(50);
      
      // LED off for 50ms
      for (byte i=0; i<MAX_CHANNEL_PAIRS; i++) {
        setLedPWMOutputs(i, 0, 0);
      }
      delay(50);
      
      // LED on for 50ms to 250ms
      for (byte i=0; i<MAX_CHANNEL_PAIRS; i++) {
        setLedPWMOutputs(i, maxLightLevel, maxLightLevel);
      }
      delay(random(50,250));           
      
      // set the LED back to normal levels for 50ms to 1sec
      for (byte i=0; i<MAX_CHANNEL_PAIRS; i++) {
        setLedPWMOutputs(i, aWhiteLevel, aBlueLevel);
      }
      delay(random(50,1000));            
      var++;
    }

    Serial.print("##LIGHTNING x");
    Serial.print(numberOfFlashes, DEC);
    Serial.print(" @");
    Serial.println(maxLightLevel,DEC);
}


/******************************************************************************************
 * GET DATE DS1307
 *
 * Gets the date and time from the ds1307
 **/
void getDateDs1307()
{
  Wire.beginTransmission(DS1307_I2C_ADDRESS);
  Wire.send(0x00);
  Wire.endTransmission();

  Wire.requestFrom(DS1307_I2C_ADDRESS, 7);

  // A few of these need masks because certain bits are control bits
  second     = bcdToDec(Wire.receive() & 0x7f);
  minute     = bcdToDec(Wire.receive());
  hour       = bcdToDec(Wire.receive() & 0x3f);  // Need to change this if 12 hour am/pm
  dayOfWeek  = bcdToDec(Wire.receive());
  dayOfMonth = bcdToDec(Wire.receive());
  month      = bcdToDec(Wire.receive());
  year       = bcdToDec(Wire.receive());
}

/******************************************************************************************
 * DUMP CURVE
 *
 * Print out to the serial port today's dcwWhiteCurve
 **/
void dumpCurve( void ) {
  Serial.println("DUMP CURVE:");
  Serial.print("D/M:");
  Serial.print(dayOfMonth, DEC);
  Serial.print("/");
  Serial.println(month, DEC);

  Serial.println("Index,Time,Level");
  for (int i=0; i < BASICDAYCURVESIZE; i++) {
    Serial.print(i, DEC);
    Serial.print(",");
    Serial.print(dcwWhiteCurve[i].time, DEC);
    Serial.print(",");
    Serial.print(dcwWhiteCurve[i].level, DEC);
    Serial.println();
  }
  Serial.println("END W");
  for (int i=0; i < BASICDAYCURVESIZE; i++) {
    Serial.print(i, DEC);
    Serial.print(",");
    Serial.print(dcwBlueCurve[i].time, DEC);
    Serial.print(",");
    Serial.print(dcwBlueCurve[i].level, DEC);
    Serial.println();
  }
  Serial.println("END B");
  Serial.println();
  
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
void getCloudSegment(byte cloudIndex, byte cloudSegIndex, unsigned int *strTime, byte *strLevel, unsigned int *finTime, byte *finLevel,
                                                          unsigned int *bStrTime, byte *bStrLevel, unsigned int *bFinTime, byte *bFinLevel) {
  unsigned int clSegStrTime;
  unsigned int wClSegStrLevel;
  unsigned int bClSegStrLevel;
  unsigned int clSegFinTime;
  unsigned int wClSegFinLevel;
  unsigned int bClSegFinLevel;
  _segment     clSegStrSeg;
  _segment     clSegFinSeg;
  _segment     bClSegStrSeg;
  _segment     bClSegFinSeg;
  
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
  getSegment(clSegStrTime, &clSegStrSeg.strTime, &clSegStrSeg.strLevel, &clSegStrSeg.finTime, &clSegStrSeg.finLevel,
                           &bClSegStrSeg.strTime, &bClSegStrSeg.strLevel, &bClSegStrSeg.finTime, &bClSegStrSeg.finLevel);

  getSegment(clSegFinTime, &clSegFinSeg.strTime, &clSegFinSeg.strLevel, &clSegFinSeg.finTime, &clSegFinSeg.finLevel,
                           &bClSegFinSeg.strTime, &bClSegFinSeg.strLevel, &bClSegFinSeg.finTime, &bClSegFinSeg.finLevel); 
                           
  // Map to find original level, then apply reductors
  wClSegStrLevel = map(clSegStrTime, clSegStrSeg.strTime, clSegStrSeg.finTime, (unsigned int) clSegStrSeg.strLevel, (unsigned int) clSegStrSeg.finLevel);
  wClSegFinLevel = map(clSegFinTime, clSegFinSeg.strTime, clSegFinSeg.finTime, (unsigned int) clSegFinSeg.strLevel, (unsigned int) clSegFinSeg.finLevel);

  bClSegStrLevel = map(clSegStrTime, bClSegStrSeg.strTime, bClSegStrSeg.finTime, (unsigned int) bClSegStrSeg.strLevel, (unsigned int) bClSegStrSeg.finLevel);
  bClSegFinLevel = map(clSegFinTime, bClSegFinSeg.strTime, bClSegFinSeg.finTime, (unsigned int) bClSegFinSeg.strLevel, (unsigned int) bClSegFinSeg.finLevel);

  switch (clouds[cloudIndex].type) {
    case SHORT_CLOUD:         
      wClSegStrLevel = (wClSegStrLevel * (100U - (unsigned int) shortCloud[cloudSegIndex].level)/100U);
      wClSegFinLevel = (wClSegFinLevel * (100U - (unsigned int) shortCloud[cloudSegIndex+1].level)/100U);
      bClSegStrLevel = (bClSegStrLevel * (100U - (unsigned int) shortCloud[cloudSegIndex].level)/100U);
      bClSegFinLevel = (bClSegFinLevel * (100U - (unsigned int) shortCloud[cloudSegIndex+1].level)/100U);
      break;

    case LONG_CLOUD:      
      wClSegStrLevel = (wClSegStrLevel * (100U - (unsigned int) longCloud[cloudSegIndex].level)/100U);
      wClSegFinLevel = (wClSegFinLevel * (100U - (unsigned int) longCloud[cloudSegIndex+1].level)/100U);
      bClSegStrLevel = (bClSegStrLevel * (100U - (unsigned int) longCloud[cloudSegIndex].level)/100U);
      bClSegFinLevel = (bClSegFinLevel * (100U - (unsigned int) longCloud[cloudSegIndex+1].level)/100U);
      break;    

    case THUNDERSTORM_CLOUD:  
      wClSegStrLevel = (wClSegStrLevel * (100U - (unsigned int) thunderstormCloud[cloudSegIndex].level)/100U);
      wClSegFinLevel = (wClSegFinLevel * (100U - (unsigned int) thunderstormCloud[cloudSegIndex+1].level)/100U);
      bClSegStrLevel = (bClSegStrLevel * (100U - (unsigned int) thunderstormCloud[cloudSegIndex].level)/100U);
      bClSegFinLevel = (bClSegFinLevel * (100U - (unsigned int) thunderstormCloud[cloudSegIndex+1].level)/100U);
      break;    

    default: return;    // ERROR!!!  
  }

  *strTime  = clSegStrTime;
  *strLevel = (byte) wClSegStrLevel;
  *finTime  = clSegFinTime;
  *finLevel = (byte) wClSegFinLevel;

  *bStrTime  = clSegStrTime;
  *bStrLevel = (byte) bClSegStrLevel;
  *bFinTime  = clSegFinTime;
  *bFinLevel = (byte) bClSegFinLevel;

}

/**************************************************************************
 * GET LEVEL
 *
 * Returns the expected level for a given moment in time
 * and informs if inside a thunderstorm (may be used for 
 * lightning production)
 **/
void getLevel(unsigned int now, boolean *inThunderstorm, byte *whiteLevel, byte *blueLevel) {

  byte cloudIndex;
  byte cloudSegIndex;
  _segment wSeg;
  _segment bSeg;
  
  *inThunderstorm = false;
  cloudIndex = insideCloud(now);
  
  if (cloudIndex == NO_CLOUD) {
      // Not in a cloud, just map the position to the basic day curve
      getSegment(now, &wSeg.strTime, &wSeg.strLevel, &wSeg.finTime, &wSeg.finLevel,
                      &bSeg.strTime, &bSeg.strLevel, &bSeg.finTime, &bSeg.finLevel);
    
  } else {
      // OK, we're in a cloud....
      // Get first cloud segment
      cloudSegIndex = 0;
      getCloudSegment(cloudIndex, cloudSegIndex, &wSeg.strTime, &wSeg.strLevel, &wSeg.finTime, &wSeg.finLevel,
                                                 &bSeg.strTime, &bSeg.strLevel, &bSeg.finTime, &bSeg.finLevel);
    
      while (wSeg.finTime < now) {
          // now isn't in this cloud segment, so get the next one and check
          cloudSegIndex++;
          getCloudSegment(cloudIndex, cloudSegIndex, &wSeg.strTime, &wSeg.strLevel, &wSeg.finTime, &wSeg.finLevel,
                                                     &bSeg.strTime, &bSeg.strLevel, &bSeg.finTime, &bSeg.finLevel);
      }
    
      // Inform if we're in a thunderstorm cloud
      if (clouds[cloudIndex].type == THUNDERSTORM_CLOUD) {
          *inThunderstorm = true;
      }
  }
  
  *whiteLevel = map(now, wSeg.strTime, wSeg.finTime, wSeg.strLevel, wSeg.finLevel);
  *blueLevel = map(now, bSeg.strTime, bSeg.finTime, bSeg.strLevel, bSeg.finLevel);
}
  

  
/**************************************************************************
 * GET SEGMENT
 *
 * Sets the start andfinish time and level variables with the waypoints of the segment
 * in which the time "when" is contained inside
 **/
void getSegment(int when, unsigned int *wStrTime, byte *wStrLevel, unsigned int *wFinTime, byte *wFinLevel,
                          unsigned int *bStrTime, byte *bStrLevel, unsigned int *bFinTime, byte *bFinLevel) {
  
  int index = 0;
  for (int i=1; i < BASICDAYCURVESIZE ; i++ ) {
    if (when < dcwWhiteCurve[i].time) {
      index = i-1;
      i=BASICDAYCURVESIZE;
    }
  }
  
  *wStrTime = dcwWhiteCurve[index].time;
  *wStrLevel = dcwWhiteCurve[index].level;
  *wFinTime = dcwWhiteCurve[index+1].time;
  *wFinLevel = dcwWhiteCurve[index+1].level;

  index = 0;
  for (int i=1; i < BASICDAYCURVESIZE ; i++ ) {
    if (when < dcwBlueCurve[i].time) {
      index = i-1;
      i=BASICDAYCURVESIZE;
    }
  }
  
  *bStrTime = dcwBlueCurve[index].time;
  *bStrLevel = dcwBlueCurve[index].level;
  *bFinTime = dcwBlueCurve[index+1].time;
  *bFinLevel = dcwBlueCurve[index+1].level;
}

/***************************************************************
* Blinks the light on the Arduino board as a heartbeat
* so I cansee the board is not frozen
**/
void heartbeat() {
    digitalWrite(13, heartbeatLevel);   // set the LED on
    if (heartbeatLevel == HIGH) {
      heartbeatLevel = LOW;
    } else {
      heartbeatLevel = HIGH;
    }
}  

/**************************************************************************
 * INSIDE CLOUD
 *
 * Returns the index of a cloud if the moment in time is inside a cloud
 * or the constant NO_CLOUD if not
 **/
byte insideCloud(unsigned int now) {

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

  unsigned int wSunriseStart, bSunriseStart;
  unsigned int wSunsetFinish, bSunsetFinish;
  unsigned int wFadeDuration, bFadeDuration;
  unsigned int wFadeStep, bFadeStep;
  
  //------------- BASIC CURVE ------------- 
  wFadeDuration = (unsigned int) map((unsigned int) aDay, 1U, (unsigned int) daysInMonth[aMonth-1], (unsigned int) minFadeDuration[aMonth-1], (unsigned int) maxFadeDuration[aMonth-1]);
  bFadeDuration = wFadeDuration + 60U;
  wFadeDuration = wFadeDuration - 60U;
  
  wSunriseStart = (unsigned int) map((unsigned int) aDay, 1U, (unsigned int) daysInMonth[aMonth-1], (unsigned int) minSunriseStart[aMonth-1], (unsigned int) maxSunriseStart[aMonth-1]);
  bSunriseStart = wSunriseStart - 60U;
  wSunriseStart = wSunriseStart + 60U;
  
  wSunsetFinish = (unsigned int) map((unsigned int) aDay, 1U, (unsigned int) daysInMonth[aMonth-1], (unsigned int) minSunsetFinish[aMonth-1], (unsigned int) maxSunsetFinish[aMonth-1]);
  bSunsetFinish = wSunsetFinish + 60U;
  wSunsetFinish = wSunsetFinish - 60U;
  
  // 30 transforms "1 min" in "2 secs":
  wFadeDuration = wFadeDuration * 30U;
  bFadeDuration = bFadeDuration * 30U;
  wSunriseStart = wSunriseStart * 30U;
  wSunsetFinish = wSunsetFinish * 30U;
  bSunriseStart = bSunriseStart * 30U;
  bSunsetFinish = bSunsetFinish * 30U;
  wFadeStep = wFadeDuration / 5U;
  bFadeStep = bFadeDuration / 5U;


  dcwWhiteCurve[0].time = 0;
  dcwWhiteCurve[0].level = 0;

  dcwWhiteCurve[1].time = wSunriseStart;  
  dcwWhiteCurve[1].level = 0;

  dcwWhiteCurve[2].time = wSunriseStart + wFadeStep;
  dcwWhiteCurve[2].level = (WHITE_MAX * 10) / 100;

  dcwWhiteCurve[3].time = wSunriseStart + 2U*wFadeStep;
  dcwWhiteCurve[3].level = (WHITE_MAX * 30) / 100;

  dcwWhiteCurve[4].time = wSunriseStart + 3U*wFadeStep;
  dcwWhiteCurve[4].level = (WHITE_MAX * 70) / 100;

  dcwWhiteCurve[5].time = wSunriseStart + 4U*wFadeStep;
  dcwWhiteCurve[5].level = (WHITE_MAX * 90) / 100;

  dcwWhiteCurve[6].time = wSunriseStart + 5U*wFadeStep;
  dcwWhiteCurve[6].level = WHITE_MAX;

  dcwWhiteCurve[7].time = wSunsetFinish - 5U*wFadeStep;
  dcwWhiteCurve[7].level = WHITE_MAX;

  dcwWhiteCurve[8].time = wSunsetFinish - 4U*wFadeStep;
  dcwWhiteCurve[8].level = (WHITE_MAX * 90) / 100;

  dcwWhiteCurve[9].time = wSunsetFinish - 3U*wFadeStep;
  dcwWhiteCurve[9].level = (WHITE_MAX * 70) / 100;

  dcwWhiteCurve[10].time = wSunsetFinish - 2U*wFadeStep;
  dcwWhiteCurve[10].level = (WHITE_MAX * 30) / 100;

  dcwWhiteCurve[11].time = wSunsetFinish - wFadeStep;
  dcwWhiteCurve[11].level = (WHITE_MAX * 10) / 100;

  dcwWhiteCurve[12].time = wSunsetFinish;
  dcwWhiteCurve[12].level = 0;

  dcwWhiteCurve[13].time = 1440U * 30U;
  dcwWhiteCurve[13].level = 0;


  dcwBlueCurve[0].time = 0;
  dcwBlueCurve[0].level = 0;

  dcwBlueCurve[1].time = bSunriseStart;  
  dcwBlueCurve[1].level = 0;

  dcwBlueCurve[2].time = bSunriseStart + bFadeStep;
  dcwBlueCurve[2].level = (BLUE_MAX * 10) / 100;

  dcwBlueCurve[3].time = bSunriseStart + 2U*bFadeStep;
  dcwBlueCurve[3].level = (BLUE_MAX * 30) / 100;

  dcwBlueCurve[4].time = bSunriseStart + 3U*bFadeStep;
  dcwBlueCurve[4].level = (BLUE_MAX * 70) / 100;

  dcwBlueCurve[5].time = bSunriseStart + 4U*bFadeStep;
  dcwBlueCurve[5].level = (BLUE_MAX * 90) / 100;

  dcwBlueCurve[6].time = bSunriseStart + 5U*bFadeStep;
  dcwBlueCurve[6].level = BLUE_MAX;

  dcwBlueCurve[7].time = bSunsetFinish - 5U*bFadeStep;
  dcwBlueCurve[7].level = BLUE_MAX;

  dcwBlueCurve[8].time = bSunsetFinish - 4U*bFadeStep;
  dcwBlueCurve[8].level = (BLUE_MAX * 90) / 100;

  dcwBlueCurve[9].time = bSunsetFinish - 3U*bFadeStep;
  dcwBlueCurve[9].level = (BLUE_MAX * 70) / 100;

  dcwBlueCurve[10].time = bSunsetFinish - 2U*bFadeStep;
  dcwBlueCurve[10].level = (BLUE_MAX * 30) / 100;

  dcwBlueCurve[11].time = bSunsetFinish - bFadeStep;
  dcwBlueCurve[11].level = (BLUE_MAX * 10) / 100;

  dcwBlueCurve[12].time = bSunsetFinish;
  dcwBlueCurve[12].level = 0;

  dcwBlueCurve[13].time = 1440U * 30U;
  dcwBlueCurve[13].level = 0;

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

  if (!DEBUG_MODE) {
    //------------- OKTA DETERMINATION  ------------- 
    byte randNumber;
    randNumber = (byte) random(0,100);
  
    if (randNumber > cloudyDays[aMonth]) {
      // this is a mixed day, Okta 2 to 3
      okta = (byte) random(2,4);
    } else if (randNumber > clearDays[aMonth] ) {
      // this is a cloudy day, Okta 4 to 8
      okta = (byte) random(4,9);
    } else {
      // this is a clear day, Okta 0 to 1
      okta = (byte) random(0,2);
    }
  }

  Serial.print("Okta=");
  Serial.print(okta, DEC);

  setCloudSpacingAndTypes();

  Serial.print(", type1=");
  Serial.print(cloudType1, DEC);
  Serial.print(", type2=");
  Serial.print(cloudType2, DEC);
  Serial.print(", spacing=");
  Serial.println(cloudSpacing, DEC);

  currCloudCoverFinish = 0;
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
    currCloudCoverFinish=1440U*30U;
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

  if ( (now > (1440U*30U/2U)) && ((okta == 5) || (okta == 6))) {
    //Serial.println("Special days as afternoon is different from morning");
    // These are special days as afternoon is different from morning
    qtyClouds = 1;
    // Start the thunderstorm from one to two hours after midday
    clouds[0].start = (1440U*30U/2U) + (unsigned int) random(0U, 120U*30U);
    clouds[0].type = THUNDERSTORM_CLOUD;
    
    // Set cloud finish to end of day, to ensure we only get one thunderstorm
    currCloudCoverFinish = 1440U*30U;
      
  } else {
    unsigned int timePos = currCloudCoverStart;
    unsigned int cloudCount = 0;

    for (int i=0; i<(MAXCLOUDS/2); i++) {
      
      if ( (timePos > (1440U*30U/2U)) && ((okta == 5) || (okta == 6))) {
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

/********************************************************8
 * Prints the date and time, as stored in the
 * global variables used to track them
 *
 */
void printDateTime() {
    Serial.print(hour, DEC);
    Serial.print(":");
    Serial.print(minute, DEC);
    Serial.print(":");
    Serial.print(second, DEC);
    Serial.print("  ");
    Serial.print(year, DEC);
    Serial.print("-");
    Serial.print(month, DEC);
    Serial.print("-");
    Serial.print(dayOfMonth, DEC);
    Serial.print(" @");
    Serial.print(dayOfWeek, DEC);
}

void serialCommands() 
{
  int command = 0;       // This is the command char, in ascii form, sent from the serial port     
  int i;
  byte test; 
  
  if (Serial.available()) {      // Look for char in serial que and process if found
    command = Serial.read();

    if (command == 73) {      // "I" = Info
      Serial.print("Okta: ");
      Serial.println(okta,DEC);
      dumpCurve();
    }
    
    if (command == 76) {      // "L" = doLigthning based off zero
      doLightning(prevWLevel, prevBLevel);
    }

    if (command == 79) {      // "O" = Set okta and recalculate day
      if (Serial.available()) {
        command = Serial.read();
        okta = command - 48;
        setCloudSpacingAndTypes();
        currCloudCoverFinish = 0;
        Serial.print("Okta reset to: ");
        Serial.println(okta,DEC);
      }
    }
    
    if (command == 82) {      //If command = "R" Read date and time
      getDateDs1307();
      printDateTime();
      Serial.println(" ");
    }
    if (command == 84) {      //If command = "T" Set Date
      setDateDs1307();
      getDateDs1307();
      printDateTime();
      Serial.println(" ");
    }
    else if (command == 81) {      //If command = "Q" RTC1307 Memory Functions
      delay(100);     
      if (Serial.available()) {
        command = Serial.read(); 
        if (command == 49) {      //If command = "1" RTC1307 Initialize Memory - All Data will be set to 255 (0xff).  Therefore 255 or 0 will be an invalid value.  
          Wire.beginTransmission(DS1307_I2C_ADDRESS); // 255 will be the init value and 0 will be considered an error that occurs when the RTC is in Battery mode.
          Wire.send(0x08); // Set the register pointer to be just past the date/time registers.
          for (i = 1; i <= 27; i++) {
            Wire.send(0xff);
            delay(100);
          }   
          Wire.endTransmission();
          getDateDs1307();
          printDateTime();
          Serial.println(": RTC1307 Initialized Memory");
        }
        else if (command == 50) {      //If command = "2" RTC1307 Memory Dump
          getDateDs1307();
          printDateTime();
          Serial.println(": RTC 1307 Dump Begin");
          Wire.beginTransmission(DS1307_I2C_ADDRESS);
          Wire.send(0x00);
          Wire.endTransmission();
          Wire.requestFrom(DS1307_I2C_ADDRESS, 64);
          for (i = 1; i <= 64; i++) {
             test = Wire.receive();
             Serial.print(i);
             Serial.print(":");
             Serial.println(test, DEC);
          }
          Serial.println(" RTC1307 Dump end");
        } 
      }  
    }
    Serial.print("Command: ");
    Serial.println(command);     // Echo command CHAR in ascii that was sent
  }
      
  command = 0;                 // reset command 
  delay(100);
}

/****************************************************************
 * SET LED PWM OUTPUTS
 *
 * Set all the LED channels we have connected to the Arduino
 * with the right PWM light value
 * 
 * For this function the bluePwmLevel and whitePwmLevel
 * are expressed in percentage 0-100
 *****************************************************************/
void setLedPWMOutputs(byte channel, byte whitePwmLevel, byte bluePwmLevel) {
  
  byte level = 0;
  
  level = (byte) ( ((unsigned int)whitePwmLevel *255U) /100U );
  analogWrite(channels[channel].wPin, level);

  level = (byte) ( ((unsigned int)bluePwmLevel *255U) /100U );
  analogWrite(channels[channel].bPin, level);
  
} 

/************************************************************
// 1) Sets the date and time on the ds1307
// 2) Starts the clock
// 3) Sets hour mode to 24 hour clock
// Assumes you're passing in valid numbers, Probably need to put in checks for valid numbers.
// Format: ssmmhhWDDMMYY  (W=Day of the week, Sunday = 0)
*/ 
void setDateDs1307()
{

   second = (byte) ((Serial.read() - 48) * 10 + (Serial.read() - 48)); // Use of (byte) type casting and ascii math to achieve result.  
   minute = (byte) ((Serial.read() - 48) *10 +  (Serial.read() - 48));
   hour  = (byte) ((Serial.read() - 48) *10 +  (Serial.read() - 48));
   dayOfWeek = (byte) (Serial.read() - 48);
   dayOfMonth = (byte) ((Serial.read() - 48) *10 +  (Serial.read() - 48));
   month = (byte) ((Serial.read() - 48) *10 +  (Serial.read() - 48));
   year= (byte) ((Serial.read() - 48) *10 +  (Serial.read() - 48));
   Wire.beginTransmission(DS1307_I2C_ADDRESS);
   Wire.send(0x00);
   Wire.send(decToBcd(second));    // 0 to bit 7 starts the clock
   Wire.send(decToBcd(minute));
   Wire.send(decToBcd(hour));      // If you want 12 hour am/pm you need to set
                                   // bit 6 (also need to change readDateDs1307)
   Wire.send(decToBcd(dayOfWeek));
   Wire.send(decToBcd(dayOfMonth));
   Wire.send(decToBcd(month));
   Wire.send(decToBcd(year));
   Wire.endTransmission();
}

/**************************************************************************
 * LOOP
 *
 **/
void loop() {
  
  unsigned int now;
  byte wLevel, bLevel;
  boolean inThunder;
  byte inCloud;
  boolean minuteChanged = false;

  serialCommands();

  getDateDs1307();
  if ((hour == 0) && (minute ==00) && (dayOfMonth == 0) && (year == 0)) {
    // Communication with RTC failed, get out of loop before something
    // bad happens
    Serial.print("#");
    heartbeat();
    delay(200);
    return;
  }
  
  // If the day changed, plan the new day
  if (prevDayOfMonth != dayOfMonth) {
    Serial.println();
    Serial.println();

    printDateTime();
    Serial.println(" ");
  
    Serial.print("DofM:");
    Serial.print(prevDayOfMonth, DEC);
    Serial.print("->");
    Serial.println(dayOfMonth, DEC);
    prevDayOfMonth = dayOfMonth;
    planNewDay(month, dayOfMonth);
    dumpCurve();
  }

  if (!DEBUG_MODE) {
    now = (hour*1800U + minute*30U + second/2U);
  } else {
    now = debug_now;
    minute = now/60;
  }

  if (now != prevNow) {
    heartbeat();
    prevNow = now;
  }

  if (prevMinute != minute) {
    Serial.print("++");
    printDateTime();
    Serial.println(" ");
    prevMinute = minute;
    minuteChanged = true;
  }

  // Loop through the LED channel pairs getting their light levels
  for (byte i=0; i<MAX_CHANNEL_PAIRS; i++) {
    boolean channelInThunder;
    unsigned int chanDelay;
    
    // Protection against unsigned int roll backwards
    chanDelay = channels[i].channelDelay;
    if (chanDelay > now) {
      chanDelay = now;
    }    
    
    getLevel(now - chanDelay, &channelInThunder, &wLevel, &bLevel);
    setLedPWMOutputs(i, wLevel, bLevel);
    
    if (channels[i].channelDelay == 0) {
      inThunder = channelInThunder;
    }
  }

  // In the future change this to LCD output
  if ((prevWLevel != wLevel) || (prevBLevel != bLevel)) {
    inCloud = insideCloud(now);
    logLevel(now, wLevel, bLevel, inCloud, inThunder);
  }

  // If in Thunderstorm, 5% possible lighning every minute
  #define LIGHTNING_CHANCE 5
  if ((inThunder) && (minuteChanged)) {
      byte randNumber = (byte) random(0, 100);
      if (randNumber <= LIGHTNING_CHANCE) {  
          doLightning(wLevel, bLevel);
      }
  }

  prevWLevel = wLevel;
  prevBLevel = bLevel;
  prevMinute = minute;
  planNextCloudBatch(now);

}

/**************************************************************************
 * SETUP
 *
 **/
void setup() {

  Wire.begin();
  Serial.begin(9600);
  randomSeed(analogRead(0));
  heartbeatLevel = LOW;

  getDateDs1307();
  
  // Zero the key variables
  currCloudCoverStart  = 0;
  currCloudCoverFinish = 0;
  prevWLevel = 0;
  prevBLevel = 0;
  prevDayOfMonth = 0;
  dayOfMonth = 40;  // Invalid number to force planNewDay in first loop
  
  if (DEBUG_MODE) {
    
    okta=0;
    xTestRun();

    prevDayOfMonth = 0;    
    okta=1;
    xTestRun();

    prevDayOfMonth = 0;    
    okta=2;
    xTestRun();

    prevDayOfMonth = 0;    
    okta=3;
    xTestRun();

    prevDayOfMonth = 0;    
    okta=4;
    xTestRun();

    prevDayOfMonth = 0;    
    okta=5;
    xTestRun();

    prevDayOfMonth = 0;    
    okta=6;
    xTestRun();

    prevDayOfMonth = 0;    
    okta=7;
    xTestRun();

    prevDayOfMonth = 0;    
    okta=8;
    xTestRun();
  }
}

/******************************************************************************
// 1) Sets the date and time on the ds1307
// 2) Starts the clock
// 3) Sets hour mode to 24 hour clock
// Assumes you're passing in valid numbers, Probably need to put in checks for valid numbers.
//
// Format: ssmmhhWDDMMYY  (W=Day of the week, Sunday = 0)
void setDateDs1307() {
   second = (byte) ((Serial.read() - 48) * 10 + (Serial.read() - 48)); // Use of (byte) type casting and ascii math to achieve result.  
   minute = (byte) ((Serial.read() - 48) *10 +  (Serial.read() - 48));
   hour  = (byte) ((Serial.read() - 48) *10 +  (Serial.read() - 48));
   dayOfWeek = (byte) (Serial.read() - 48);
   dayOfMonth = (byte) ((Serial.read() - 48) *10 +  (Serial.read() - 48));
   month = (byte) ((Serial.read() - 48) *10 +  (Serial.read() - 48));
   year= (byte) ((Serial.read() - 48) *10 +  (Serial.read() - 48));
   Wire.beginTransmission(DS1307_I2C_ADDRESS);
   Wire.send(0x00);
   Wire.send(decToBcd(second));    // 0 to bit 7 starts the clock
   Wire.send(decToBcd(minute));
   Wire.send(decToBcd(hour));      // If you want 12 hour am/pm you need to set
                                   // bit 6 (also need to change readDateDs1307)
   Wire.send(decToBcd(dayOfWeek));
   Wire.send(decToBcd(dayOfMonth));
   Wire.send(decToBcd(month));
   Wire.send(decToBcd(year));
   Wire.endTransmission();

  printDateTime();
}
*/

void logLevel(unsigned int tNow, byte wTLevel, byte bTLevel, byte tInCloud, boolean tInThunder) 
{
  Serial.print(tNow,DEC);
  Serial.print(",");
  Serial.print(wTLevel,DEC);
  Serial.print(",");
  Serial.print(bTLevel,DEC);
  Serial.print(",");
  Serial.print(tInCloud,DEC);
  Serial.print(",");
  Serial.print(tInThunder,DEC);
  Serial.println();
}

//****************************************************************************************************************************************************
// Test Run
void xTestRun() {
  for (debug_now=0L; debug_now<43200U; debug_now++) {
    loop();
  }
}

/*************************************************************************
// XUNIT TESTS OF FUNCTIONS 
//
// Test Driven Development, saves me a lot of time in debugging changes....
//
void xUnitTests() {
  
  // Setup
  
  dcwWhiteCurve[0].time= 0;
  dcwWhiteCurve[0].level= 0;
  dcwWhiteCurve[1].time= 300*30;
  dcwWhiteCurve[1].level= 10;
  dcwWhiteCurve[2].time= 500*30;
  dcwWhiteCurve[2].level= 90;
  dcwWhiteCurve[3].time= 800*30;
  dcwWhiteCurve[3].level= 95;
  dcwWhiteCurve[4].time= 1000*30;
  dcwWhiteCurve[4].level= 100;
  dcwWhiteCurve[5].time= 1100*30;
  dcwWhiteCurve[5].level= 10;
  dcwWhiteCurve[6].time= 43200;
  dcwWhiteCurve[6].level= 0;

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
  byte bLevel;
  byte level = getLevel(time, &inThunderstorm, &level, &bLevel);
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
