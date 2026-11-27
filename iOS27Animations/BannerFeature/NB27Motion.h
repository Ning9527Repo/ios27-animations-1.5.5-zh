#pragma once
#include <math.h>
#include <stddef.h>
#include <limits.h>
/* Reconstructed from GlassSuiteX 1.1-0, arm64e VA 0x6eb68.
 * Channels: scale.x, scale.y, normalized position.x, normalized position.y.
 * Sampler VA 0x40e48; keyframe builder VA 0x41064. Not a fitted spring. */
static const double NB27Duration = 0.86;
static const size_t NB27SampleCount = 217;
static const double NB27MotionNodes[16][5] = {
 {0.00,.110,.115,-.372,-.620}, {0.04,.110,.115,-.372,-.470},
 {0.08,.110,.115,-.372,-.190}, {0.12,.112,.120,-.371,.070},
 {0.15,.147,.245,-.348,.220}, {0.19,.239,.435,-.284,.280},
 {0.23,.343,.670,-.220,.272}, {0.27,.455,.873,-.152,.217},
 {0.31,.563,1.020,-.096,.154}, {0.35,.660,1.090,-.056,.085},
 {0.40,.767,1.105,-.023,.028}, {0.48,.889,1.075,.003,-.012},
 {0.57,.963,1.025,.013,-.012}, {0.66,.991,1.006,.009,-.005},
 {0.76,1.000,1.000,.001,.000}, {0.86,1.000,1.000,.000,.000}
};
static inline double NB27Clamp(double x,double a,double b) { return fmin(fmax(x,a),b); }
static inline double NB27MotionNode(size_t i,unsigned c,double elasticity) {
 double raw=NB27MotionNodes[i][c+1];
 if(elasticity==1.0)return raw;
 double values[16];unsigned weights[16],blocks=0;
 double direction=NB27MotionNodes[15][c+1]>=NB27MotionNodes[0][c+1]?1.0:-1.0;
 for(size_t k=0;k<16;k++) {
  values[blocks]=direction*NB27MotionNodes[k][c+1];weights[blocks]=1;blocks++;
  while(blocks>1&&values[blocks-2]>values[blocks-1]) {
   unsigned total=weights[blocks-2]+weights[blocks-1];
   values[blocks-2]=(values[blocks-2]*weights[blocks-2]+values[blocks-1]*weights[blocks-1])/total;
   weights[blocks-2]=total;blocks--;
  }
 }
 size_t cursor=0;double base=direction*raw;
 for(size_t block=0;block<blocks;block++) {
  if(i<cursor+weights[block]){base=direction*values[block];break;}
  cursor+=weights[block];
 }
 double first=NB27MotionNodes[0][c+1],last=NB27MotionNodes[15][c+1];
 base=NB27Clamp(base,fmin(first,last),fmax(first,last));
 return base+NB27Clamp(elasticity,0,2)*(raw-base);
}
static inline double NB27Slope(size_t i,unsigned c,double elasticity) {
 if (i==0 || i==15) return 0;
 double h0=NB27MotionNodes[i][0]-NB27MotionNodes[i-1][0];
 double h1=NB27MotionNodes[i+1][0]-NB27MotionNodes[i][0];
 double d0=(NB27MotionNode(i,c,elasticity)-NB27MotionNode(i-1,c,elasticity))/h0;
 double d1=(NB27MotionNode(i+1,c,elasticity)-NB27MotionNode(i,c,elasticity))/h1;
 if (d0*d1<=0) return 0;
 double w0=2*h1+h0,w1=2*h0+h1;
 return (w0+w1)/(w0/d0+w1/d1);
}
static inline double NB27MotionWithElasticity(double t,unsigned c,double elasticity) {
 if (c>3 || !isfinite(t)) return c<2?1:0;
 if (t<=0) return NB27MotionNode(0,c,elasticity);
 if (t>=NB27Duration) return NB27MotionNode(15,c,elasticity);
 size_t i=0; while (i<14 && t>NB27MotionNodes[i+1][0]) ++i;
 double h=NB27MotionNodes[i+1][0]-NB27MotionNodes[i][0];
 double u=(t-NB27MotionNodes[i][0])/h,u2=u*u,u3=u2*u;
 double y0=NB27MotionNode(i,c,elasticity),y1=NB27MotionNode(i+1,c,elasticity);
 double value=(2*u3-3*u2+1)*y0+(u3-2*u2+u)*h*NB27Slope(i,c,elasticity)
      +(-2*u3+3*u2)*y1+(u3-u2)*h*NB27Slope(i+1,c,elasticity);
 return elasticity==1.0?value:NB27Clamp(value,fmin(y0,y1),fmax(y0,y1));
}
static inline double NB27Motion(double t,unsigned c) {
 return NB27MotionWithElasticity(t,c,1.0);
}
static inline double NB27ScaledDuration(double transitionScale) {
 return NB27Duration*NB27Clamp(transitionScale,.5,2.0);
}
static inline double NB27MotionWithSettings(double t,unsigned c,double elasticity,double transitionScale) {
 return NB27MotionWithElasticity(t/NB27Clamp(transitionScale,.5,2.0),c,elasticity);
}
static inline double NB27ExitDuration(double nativeDuration,double motionTime,double transitionScale) {
 double scale=NB27Clamp(transitionScale,.5,2.0);
 if(!isfinite(nativeDuration)||nativeDuration<=1.0/60.0)nativeDuration=1.0/30.0;
 double unscaledDuration=nativeDuration/scale,unscaledMotion=motionTime/scale;
 double base=fmin(unscaledDuration-1.0/60.0,.48)*fmax(unscaledMotion/NB27Duration,.25);
 return NB27Clamp(base*scale,1.0/120.0,nativeDuration*.9);
}
static inline unsigned long long NB27ScaleDismissDelay(unsigned long long delay,double scale) {
 if(!isfinite(scale))scale=1.0;
 long double value=(long double)delay*(long double)NB27Clamp(scale,.5,3.0);
 if(value>=(long double)ULLONG_MAX)return ULLONG_MAX;
 return (unsigned long long)floorl(value+.5L);
}

static inline double NB27ExitOpacity(double p) {
 if(p<=.8) return 1;
 if(p>=1) return 0;
 double u=NB27Clamp((p-.8)/.2,0,1);
 return NB27Clamp(1-u*u*u*(10+u*(-15+6*u)),0,1);
}
