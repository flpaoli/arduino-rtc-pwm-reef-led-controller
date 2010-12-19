/**********************************************************************************
    Aquarium LED controller with weather simulation
    Copyright (C) 2010, Fabio Luis De Paoli

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

#define BASICDAYCURVESIZE 7
_waypoint basicDayCurve[BASICDAYCURVESIZE];


/**************************************************************************
 * GETCLOUDDURATION
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
 * GETCLOUDSEGMENT
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
 * GETLEVEL
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
 * GETSEGMENT
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
 * INSIDECLOUD
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
  Serial.begin(9600);

  Serial.println("UNIT TESTING START ##########################");
  xUnitTests();
  Serial.println("UNIT TESTING FINISH #########################");
}

//****************************************************************************************************************************************************

/**************************************************************************
 * XUNIT TESTS OF FUNCTIONS 
 *
 * Test Driven Development, saves me a lot of time in debugging changes....
 **/
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
  // segment 13
  //{ 580, 38 } ,  
  //{ 600, 0  }    

  cloudIndex = 0;
  cloudSegIndex = 5;
  getCloudSegment(cloudIndex, cloudSegIndex, &cloudSeg.strTime, &cloudSeg.strLevel, &cloudSeg.finTime, &cloudSeg.finLevel);
  if (cloudSeg.strTime != (600*30 + 100)) {
   Serial.print("Failed getCloudSegment ");
   Serial.print(cloudIndex, DEC);
   Serial.print("/");
   Serial.print(cloudSegIndex, DEC);
   Serial.print(" strTime not 100 :");
   Serial.println(cloudSeg.strTime, DEC);
  }
  correctLevel = (map(600*30+100,500*30,800*30,90,95) * (100-35)) / 100;
  if (cloudSeg.strLevel != correctLevel ) {
   Serial.print("Failed getCloudSegment ");
   Serial.print(cloudIndex, DEC);
   Serial.print("/");
   Serial.print(cloudSegIndex, DEC);
   Serial.print(" strLevel not ");
   Serial.print(correctLevel, DEC);
   Serial.print(" : ");
   Serial.println(cloudSeg.strLevel, DEC);
  }    
  if (cloudSeg.finTime != (600*30 + 200)) {
   Serial.print("Failed getCloudSegment ");
   Serial.print(cloudIndex, DEC);
   Serial.print("/");
   Serial.print(cloudSegIndex, DEC);
   Serial.print(" finTime not 200 :");
   Serial.println(cloudSeg.finTime, DEC);
  }    
  correctLevel = (map(600*30+200,500*30,800*30,90,95) * (100-40)) / 100;
  if (cloudSeg.finLevel != correctLevel) {
   Serial.print("Failed getCloudSegment ");
   Serial.print(cloudIndex, DEC);
   Serial.print("/");
   Serial.print(cloudSegIndex, DEC);
   Serial.print(" strLevel not ");
   Serial.print(correctLevel, DEC);
   Serial.print(" : ");
   Serial.println(cloudSeg.finLevel, DEC);
  }    
  
  cloudSegIndex = 13;
  getCloudSegment(cloudIndex, cloudSegIndex, &cloudSeg.strTime, &cloudSeg.strLevel, &cloudSeg.finTime, &cloudSeg.finLevel);
  if (cloudSeg.strTime != (600*30 + 580)) {
   Serial.print("Failed getCloudSegment ");
   Serial.print(cloudIndex, DEC);
   Serial.print("/");
   Serial.print(cloudSegIndex, DEC);
   Serial.print(" strTime not 580 :");
   Serial.println(cloudSeg.strTime, DEC);
  }    
  correctLevel = (map(600*30+580,500*30,800*30,90,95) * (100-38)) / 100;
  if (cloudSeg.strLevel != correctLevel) {
   Serial.print("Failed getCloudSegment ");
   Serial.print(cloudIndex, DEC);
   Serial.print("/");
   Serial.print(cloudSegIndex, DEC);
   Serial.print(" strLevel not ");
   Serial.print(correctLevel, DEC);
   Serial.print(" : ");
   Serial.println(cloudSeg.strLevel, DEC);
  }    
  if (cloudSeg.finTime != (600*30 + 600)) {
   Serial.print("Failed getCloudSegment ");
   Serial.print(cloudIndex, DEC);
   Serial.print("/");
   Serial.print(cloudSegIndex, DEC);
   Serial.print(" finTime not 600 :");
   Serial.println(cloudSeg.finTime, DEC);
  }    
  correctLevel = (map(600*30+600,500*30,800*30,90,95) * (100-0)) / 100;
  if (cloudSeg.finLevel != correctLevel) {
   Serial.print("Failed getCloudSegment ");
   Serial.print(cloudIndex, DEC);
   Serial.print("/");
   Serial.print(cloudSegIndex, DEC);
   Serial.print(" strLevel not ");
   Serial.print(correctLevel, DEC);
   Serial.print(" : ");
   Serial.println(cloudSeg.finLevel, DEC);
  }    

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
