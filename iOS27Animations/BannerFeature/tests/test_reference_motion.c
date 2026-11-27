#include <assert.h>
#include <stdio.h>
#include "../NB27ReferenceMotion.h"
static unsigned long cases;
static void near(double a,double b) { assert(isfinite(a)&&isfinite(b)&&fabs(a-b)<1e-9);cases++; }
int main(void) {
 for(unsigned width=100;width<=500;width+=20)
 for(unsigned height=20;height<=180;height+=20)
 for(unsigned a=0;a<=10;a++) {
  double w=width,h=height,ax=a/10.0,ay=(10-a)/10.0;
  for(unsigned lw=20;lw<=150;lw+=5) {
   double c=NB27ReferenceCompactCenter(80,lw,w,1);
   double rtl=NB27ReferenceCompactCenter(80,lw,w,-1);
   near(c-w*NB27MotionNodes[0][1]*.5,80-lw*.5);
   near(rtl+w*NB27MotionNodes[0][1]*.5,80+lw*.5);
  }
  // Default geometry must be algebraically identical to the recovered path.
  for(unsigned i=0;i<217;i++) {
   double t=NB27Duration*i/216.0;
   double dx=w*NB27MotionNodes[0][3],dy=h*NB27MotionNodes[0][4];
   NB27ReferencePose p=NB27ReferenceAt(t,w,h,ax,ay,dx,dy);
   near(p.scaleX,NB27Motion(t,0)-1);near(p.scaleY,NB27Motion(t,1)-1);
   near(p.x,fma(p.scaleX,w*(ax-.5),w*NB27Motion(t,2)));
   near(p.y,fma(p.scaleY,h*(ay-.5),h*NB27Motion(t,3)));
  }
  double dx=-.38*w,dy=-.66*h;
  NB27ReferencePose p=NB27ReferenceAt(0,w,h,ax,ay,dx,dy);
  // Position compensates non-central anchors: actual visual center must be at
  // the measured compact origin regardless of the CALayer anchorPoint.
  near(p.x+(.5-ax)*w*p.scaleX,dx);near(p.y+(.5-ay)*h*p.scaleY,dy);
  NB27ReferencePose end=NB27ReferenceAt(NB27Duration,w,h,ax,ay,dx,dy);
  near(end.scaleX,0);near(end.scaleY,0);near(end.x,0);near(end.y,0);
  // Mirroring changes only the horizontal coordinate/anchor, not timing.
  for(unsigned i=0;i<32;i++) {
   double start=NB27Duration*i/31.0;
   NB27ReferencePose at=NB27ReferenceAt(start,w,h,ax,ay,dx,dy);
   NB27ReferencePose rtl=NB27ReferenceAt(start,w,h,1-ax,ay,-dx,dy);
   near(at.x,-rtl.x);near(at.y,rtl.y);near(at.scaleX,rtl.scaleX);
   NB27ReferencePose join=NB27ReferenceReverse(start,start,w,h,ax,ay,dx,dy);
   near(join.scaleX,0);near(join.scaleY,0);near(join.x,0);near(join.y,0);
   NB27ReferencePose rev=NB27ReferenceReverse(0,start,w,h,ax,ay,dx,dy);
   near(rev.scaleX+at.scaleX,p.scaleX);near(rev.scaleY+at.scaleY,p.scaleY);
   near(rev.x+at.x,p.x);near(rev.y+at.y,p.y);
   const double bx=.72, by=1.12;
   NB27ReferencePose scaled=NB27ReferenceLayerAt(start,w,h,ax,ay,dx,dy,bx,by);
   NB27ReferencePose compact=NB27ReferenceLayerAt(0,w,h,ax,ay,dx,dy,bx,by);
   NB27ReferencePose collapse=NB27ReferenceLayerReverse(0,start,w,h,ax,ay,dx,dy,bx,by);
   near(bx+compact.scaleX,bx*NB27Motion(0,0));
   near(by+compact.scaleY,by*NB27Motion(0,1));
   near(compact.x+(.5-ax)*w*compact.scaleX,dx);
   near(compact.y+(.5-ay)*h*compact.scaleY,dy);
   near(scaled.scaleX+collapse.scaleX,compact.scaleX);
   near(scaled.scaleY+collapse.scaleY,compact.scaleY);
   near(scaled.x+collapse.x,compact.x);near(scaled.y+collapse.y,compact.y);
  }
 }
 printf("PASS: %lu reference coordinate/mirroring/interrupted-exit assertions; not UIKit runtime\n",cases);
 return 0;
}
