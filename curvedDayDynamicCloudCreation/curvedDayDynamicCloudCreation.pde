// Definition of a light waypoint
struct _waypoint {
  unsigned int time;   // in 2 seconds, 1h=900 2secs, 24h = 43200 2secs
  byte         level;
};

#define BASICDAYCURVESIZE 7
_waypoint basicDayCurve[7];

// Definition of a segment
struct _segment {
  unsigned int strTime;  // Start
  byte         strLevel;  // Start
  unsigned int finTime;  // Finish
  byte         finLevel;  // Finish
};

/**************************************************************************
 * GETSEGMENT
 *
 * Sets the start andfinish time variables with the waypoints of the segment
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
 * test Driven Development, saves me a lot of time in debugging changes....
 **/
void xUnitTests() {
  
  // Setup
  
  basicDayCurve[0].time= 0;
  basicDayCurve[0].level= 0;
  basicDayCurve[1].time= 300;
  basicDayCurve[1].level= 10;
  basicDayCurve[2].time= 500;
  basicDayCurve[2].level= 90;
  basicDayCurve[3].time= 800;
  basicDayCurve[3].level= 95;
  basicDayCurve[4].time= 1000;
  basicDayCurve[4].level= 100;
  basicDayCurve[5].time= 1100;
  basicDayCurve[5].level= 10;
  basicDayCurve[6].time= 43200;
  basicDayCurve[6].level= 0;
  
  // Tests
  
  _segment aSeg;

  getSegment(100, &aSeg.strTime, &aSeg.strLevel, &aSeg.finTime, &aSeg.finLevel);
  if (aSeg.strTime != 0) {
   Serial.println("Failed getSegment 100 str time");
  }
  if (aSeg.strLevel != 0) {
   Serial.println("Failed getSegment 100 str level");
  }
  if (aSeg.finTime != 300) {
   Serial.println("Failed getSegment 100 fin time");
  }
  if (aSeg.finLevel != 10) {
   Serial.println("Failed getSegment 100 fin level");
  }
  
  
  getSegment(900, &aSeg.strTime, &aSeg.strLevel, &aSeg.finTime, &aSeg.finLevel);
  if (aSeg.strTime != 800) {
   Serial.println("Failed getSegment 900 str time");
  }
  if (aSeg.strLevel != 95) {
   Serial.println("Failed getSegment 900 str level");
  }
  if (aSeg.finTime != 1000) {
   Serial.println("Failed getSegment 900 fin time");
  }
  if (aSeg.finLevel != 100) {
   Serial.println("Failed getSegment 900 fin level");
  }
  
}
