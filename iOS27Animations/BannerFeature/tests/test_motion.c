#include <assert.h>
#include <stdio.h>
#include "../NB27Motion.h"
static void closeEnough(double x,double y) { assert(isfinite(x)&&fabs(x-y)<1e-10); }
int main(void) {
 unsigned long cases=0;
 for(unsigned c=0;c<4;c++) {
  for(size_t i=0;i<16;i++) {
   double value=NB27MotionWithElasticity(NB27MotionNodes[i][0],c,1.0);
   closeEnough(value,NB27MotionNodes[i][c+1]);cases++;
  }
  for(size_t i=0;i<15;i++)for(size_t j=0;j<=1000;j++) {
   double t=NB27MotionNodes[i][0]+(NB27MotionNodes[i+1][0]-NB27MotionNodes[i][0])*j/1000;
   double lo=fmin(NB27MotionNode(i,c,0.0),NB27MotionNode(i+1,c,0.0));
   double hi=fmax(NB27MotionNode(i,c,0.0),NB27MotionNode(i+1,c,0.0));
   double base=NB27MotionWithElasticity(t,c,0.0),value=NB27MotionWithElasticity(t,c,1.0);
   assert(isfinite(base)&&base>=lo-1e-12&&base<=hi+1e-12);
   assert(isfinite(value));
   closeEnough(NB27MotionWithSettings(t,c,1.0,1.0),NB27Motion(t,c));cases++;
  }
 }
 assert(NB27SampleCount==217);closeEnough(NB27Duration,.86);
 closeEnough(NB27ScaledDuration(.5),.43);closeEnough(NB27ScaledDuration(1),.86);
 closeEnough(NB27ScaledDuration(2),1.72);
 assert(NB27ScaleDismissDelay(1000,.5)==500);
 assert(NB27ScaleDismissDelay(1000,1.0)==1000);
 assert(NB27ScaleDismissDelay(1000,3.0)==3000);
 assert(NB27ScaleDismissDelay(1000,9.0)==3000);
 assert(NB27ScaleDismissDelay(ULLONG_MAX,3.0)==ULLONG_MAX);
 for(unsigned i=0;i<=100;i++) {
  double t=NB27Duration*i/100.0;
  closeEnough(NB27MotionWithSettings(t,1,1.0,.5),NB27MotionWithElasticity(t/.5,1,1.0));
  closeEnough(NB27MotionWithSettings(t,1,1.0,2.0),NB27MotionWithElasticity(t/2.0,1,1.0));cases++;
 }
 assert(NB27MotionWithElasticity(.40,1,0.0)<NB27MotionWithElasticity(.40,1,1.0));
 for(unsigned c=0;c<4;c++)for(size_t i=0;i<15;i++)for(size_t j=0;j<=500;j++) {
  double t=NB27MotionNodes[i][0]+(NB27MotionNodes[i+1][0]-NB27MotionNodes[i][0])*j/500.0;
  double a=NB27MotionWithElasticity(t,c,0.0);
  double lo=fmin(NB27MotionNode(i,c,0.0),NB27MotionNode(i+1,c,0.0));
  double hi=fmax(NB27MotionNode(i,c,0.0),NB27MotionNode(i+1,c,0.0));
  assert(a>=lo-1e-12&&a<=hi+1e-12);cases++;
 }
 for(size_t i=0;i<NB27SampleCount;i++) {
  double p=(double)i/(NB27SampleCount-1),a=NB27ExitOpacity(p);
  assert(a>=0&&a<=1);if(p<=.8)closeEnough(a,1);cases++;
 }
 closeEnough(NB27ExitOpacity(1),0);closeEnough(NB27ExitOpacity(.8),1);
 closeEnough(NB27ExitOpacity(.9),.5);
 for(unsigned width=100;width<=500;width+=10)for(unsigned anchor=0;anchor<=10;anchor++)
 for(unsigned sample=0;sample<217;sample++) {
  double t=.86*sample/216,x=NB27Motion(t,0)-1,delta=width*NB27Motion(t,2);
  double px=fma(x,width*(anchor/10.0-.5),delta);
  double rtl=fma(x,width*((1-anchor/10.0)-.5),-delta);
  closeEnough(px,-rtl);assert(isfinite(px));cases++;
 }
 for(unsigned ms=80;ms<=1000;ms+=10)for(unsigned i=0;i<217;i++) {
  double start=.86*i/216,duration=NB27ExitDuration(ms/1000.0,start,1.0);
  assert(duration>0&&duration<ms/1000.0);cases++;
  for(unsigned c=0;c<4;c++)closeEnough(NB27Motion(start,c)-NB27Motion(start,c),0);
 }
 printf("PASS: %lu production motion/geometry assertions; no UIKit runtime claim\n",cases);
 return 0;
}
