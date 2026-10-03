#include "../OrbShading.h"

// Salute · movimento: two sugar cubes, a small one resting tilted on the big one.
static float zolletta(float3 p, float) {
    float3 a = p - float3(-0.2, -0.28, 0);
    a.xy = a.xy * rot(0.2);
    float3 b = p - float3(0.3, 0.34, 0);
    b.xy = b.xy * rot(-0.3);
    b.yz = b.yz * rot(0.25);
    return min(sdRoundBox(a, float3(0.4), 0.07), sdRoundBox(b, float3(0.3), 0.06));
}

ORB_FORMA(zolletta)
