#pragma once
#include "NB27Motion.h"

/* The recovered four-channel timing is retained. The compact end is aligned to
 * measured native time geometry rather than assuming a fixed screen width.
 * compactDX/DY are the compact visual center minus the settled visual center,
 * in the card layer's parent coordinate space. Only bounded status-clock text
 * is parsed; notification content is never read. */
typedef struct { double scaleX,scaleY,x,y; } NB27ReferencePose;
/* The first small card and the retained line share the leading edge in the
 * recording; an adjacent focus glyph must not re-center the compact card. */
static inline double NB27ReferenceCompactCenter(double lineCenter,double lineWidth,
 double cardWidth,double direction) {
 return lineCenter+direction*(cardWidth*NB27MotionNodes[0][1]-lineWidth)*.5;
}
static inline NB27ReferencePose NB27ReferenceAt(double t,double width,double height,
 double anchorX,double anchorY,double compactDX,double compactDY) {
 double x=NB27Motion(t,0)-1,y=NB27Motion(t,1)-1;
 double rx=NB27Motion(t,2)/NB27MotionNodes[0][3];
 double ry=NB27Motion(t,3)/NB27MotionNodes[0][4];
 NB27ReferencePose p={x,y,fma(x,width*(anchorX-.5),compactDX*rx),
  fma(y,height*(anchorY-.5),compactDY*ry)};
 return p;
}
static inline NB27ReferencePose NB27ReferenceAtWithSettings(double t,double width,double height,
 double anchorX,double anchorY,double compactDX,double compactDY,double elasticity,double scale) {
 double x=NB27MotionWithSettings(t,0,elasticity,scale)-1;
 double y=NB27MotionWithSettings(t,1,elasticity,scale)-1;
 double rx=NB27MotionWithSettings(t,2,elasticity,scale)/NB27MotionNodes[0][3];
 double ry=NB27MotionWithSettings(t,3,elasticity,scale)/NB27MotionNodes[0][4];
 NB27ReferencePose p={x,y,fma(x,width*(anchorX-.5),compactDX*rx),fma(y,height*(anchorY-.5),compactDY*ry)};
 return p;
}
static inline NB27ReferencePose NB27ReferenceReverse(double t,double start,
 double width,double height,double anchorX,double anchorY,
 double compactDX,double compactDY) {
 NB27ReferencePose a=NB27ReferenceAt(t,width,height,anchorX,anchorY,compactDX,compactDY);
 NB27ReferencePose b=NB27ReferenceAt(start,width,height,anchorX,anchorY,compactDX,compactDY);
 NB27ReferencePose result={a.scaleX-b.scaleX,a.scaleY-b.scaleY,a.x-b.x,a.y-b.y};
 return result;
}
static inline NB27ReferencePose NB27ReferenceReverseWithSettings(double t,double start,double width,double height,
 double anchorX,double anchorY,double compactDX,double compactDY,double elasticity,double scale) {
 NB27ReferencePose a=NB27ReferenceAtWithSettings(t,width,height,anchorX,anchorY,compactDX,compactDY,elasticity,scale);
 NB27ReferencePose b=NB27ReferenceAtWithSettings(start,width,height,anchorX,anchorY,compactDX,compactDY,elasticity,scale);
 NB27ReferencePose result={a.scaleX-b.scaleX,a.scaleY-b.scaleY,a.x-b.x,a.y-b.y};return result;
}
static inline NB27ReferencePose NB27ReferenceLayerAtWithSettings(double t,double width,double height,
 double anchorX,double anchorY,double compactDX,double compactDY,double baseX,double baseY,double elasticity,double scale) {
 NB27ReferencePose p=NB27ReferenceAtWithSettings(t,width*baseX,height*baseY,anchorX,anchorY,compactDX,compactDY,elasticity,scale);
 p.scaleX*=baseX;p.scaleY*=baseY;return p;
}
static inline NB27ReferencePose NB27ReferenceLayerReverseWithSettings(double t,double start,double width,double height,
 double anchorX,double anchorY,double compactDX,double compactDY,double baseX,double baseY,double elasticity,double scale) {
 NB27ReferencePose p=NB27ReferenceReverseWithSettings(t,start,width*baseX,height*baseY,anchorX,anchorY,compactDX,compactDY,elasticity,scale);
 p.scaleX*=baseX;p.scaleY*=baseY;return p;
}
/* Convert the recovered unit-scale deltas to the actual additive CA channels.
 * The position terms already compensate for the base-scaled card dimensions. */
static inline NB27ReferencePose NB27ReferenceLayerAt(double t,double width,double height,
 double anchorX,double anchorY,double compactDX,double compactDY,double baseX,double baseY) {
 NB27ReferencePose p=NB27ReferenceAt(t,width*baseX,height*baseY,anchorX,anchorY,compactDX,compactDY);
 p.scaleX*=baseX;p.scaleY*=baseY;
 return p;
}
static inline NB27ReferencePose NB27ReferenceLayerReverse(double t,double start,double width,double height,
 double anchorX,double anchorY,double compactDX,double compactDY,double baseX,double baseY) {
 NB27ReferencePose p=NB27ReferenceReverse(t,start,width*baseX,height*baseY,anchorX,anchorY,compactDX,compactDY);
 p.scaleX*=baseX;p.scaleY*=baseY;
 return p;
}
