#include "../OrbShading.h"

// Chat · casa: a coffee bean, two oval halves leaning a little, split by the groove down the middle.
static float chicco_caffe(float3 p, float) {
    p.xy = p.xy * rot(0.5);
    float3 q = float3(abs(p.x), p.y, p.z);
    float lower = sdRoundCone(q, float3(0.32, -0.45, 0), float3(0.32, 0, 0), 0.20, 0.29);
    float upper = sdRoundCone(q, float3(0.32, 0, 0), float3(0.32, 0.45, 0), 0.29, 0.20);
    float slit = sdSegment(p, float3(0, -0.45, -0.06), float3(0, 0.45, -0.06), 0.09);
    return min(min(lower, upper), slit);
}

ORB_FORMA(chicco_caffe)
