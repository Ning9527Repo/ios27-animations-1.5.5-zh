#include <assert.h>
#include <stdio.h>
#include "../NB27ReferenceMotion.h"
static unsigned long cases;
static void near(double a,double b) { if(!(isfinite(a)&&isfinite(b)&&fabs(a-b)<1e-9))fprintf(stderr,"near failed: %.12g != %.12g (case %lu)\n",a,b,cases+1);assert(isfinite(a)&&isfinite(b)&&fabs(a-b)<1e-9);cases++; }
int main(void) {
 for(unsigned width=100;width<=500;width+=20)
 for(unsigned height=20;height<=180;height+=20)
 for(unsigned a=0;a<=10;a++) {
  double w=width,h=height,ax=a/10.0,ay=(10-a)/10.0;
  for(unsigned lw=20;lw<=150;lw+=5) {
   double sx=NB27ReferenceCompactScale(lw,w),sy=NB27ReferenceCompactScale(2,h);
   assert(sx>0&&sx<=.98&&sy>0&&sy<.25);
   near(sx,fmin(.98,(double)lw/w));
   near(sy,2.0/h);
  }
  // Default geometry must be algebraically identical to the recovered path.
  for(unsigned i=0;i<217;i++) {
   double t=NB27Duration*i/216.0;
   double dx=w*NB27MotionNodes[0][3],dy=h*NB27MotionNodes[0][4];
   NB27ReferencePose p=NB27ReferenceAt(t,w,h,ax,ay,dx,dy);
   near(p.scaleX,NB27Motion(t,0)-1);near(p.scaleY,NB27Motion(t,1)-1);
   double lineScaleX=NB27ReferenceCompactScale(fmin(64,w*.3),w);
   double lineScaleY=NB27ReferenceCompactScale(2,h);
   NB27ReferencePose compact=NB27ReferenceCompactAtWithSettings(t,w,h,ax,ay,dx,dy,lineScaleX,lineScaleY,1.0,1.0);
   NB27ReferencePose compactRTL=NB27ReferenceCompactAtWithSettings(t,w,h,1-ax,ay,-dx,dy,lineScaleX,lineScaleY,1.0,1.0);
   near(compact.x,-compactRTL.x);near(compact.y,compactRTL.y);
   near(compact.scaleX,compactRTL.scaleX);near(compact.scaleY,compactRTL.scaleY);
   NB27ReferencePose compactStart=NB27ReferenceLayerCompactAtWithSettings(0,w,h,ax,ay,dx,dy,.72,1.12,lineScaleX,lineScaleY,1.0,1.0);
   NB27ReferencePose compactEnd=NB27ReferenceLayerCompactAtWithSettings(NB27Duration,w,h,ax,ay,dx,dy,.72,1.12,lineScaleX,lineScaleY,1.0,1.0);
   NB27ReferencePose compactExit=NB27ReferenceLayerCompactReverseWithSettings(t,NB27Duration,w,h,ax,ay,dx,dy,.72,1.12,lineScaleX,lineScaleY,1.0,1.0);
   near(.72+compactStart.scaleX,.72*lineScaleX);near(1.12+compactStart.scaleY,1.12*lineScaleY);
   near(compactStart.x+(.5-ax)*w*compactStart.scaleX,dx);
   near(compactStart.y+(.5-ay)*h*compactStart.scaleY,dy);
   near(compactEnd.scaleX,0);near(compactEnd.scaleY,0);near(compactEnd.x,0);near(compactEnd.y,0);
   NB27ReferencePose compactAtT=NB27ReferenceLayerCompactAtWithSettings(t,w,h,ax,ay,dx,dy,.72,1.12,lineScaleX,lineScaleY,1.0,1.0);
   near(compactExit.scaleX,compactAtT.scaleX);near(compactExit.scaleY,compactAtT.scaleY);
   near(compactExit.x,compactAtT.x);near(compactExit.y,compactAtT.y);
   near(lineScaleX,NB27ReferenceCompactScale(fmin(64,w*.3),w));
   near(lineScaleY,NB27ReferenceCompactScale(2,h));
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
