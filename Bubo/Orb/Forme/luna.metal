#include "../OrbShading.h"

// Meteo · notte: a thick crescent facing left, a chain of round cones along an arc, fat at the middle and thin at the tips.
static float luna(float3 p, float) {
    float3 q = p - float3(0.25, 0, 0);
    float d = 9.0;
    float2 prev = float2(0);
    float rPrev = 0.0;
    for (int i = 0; i <= 10; i++) {
        float a = 1.0471976 + 4.1887902 * float(i) / 10.0;
        float2 pt = 0.60 * float2(cos(a), sin(a));
        float r = 0.05 + 0.22 * sin(3.1415927 * float(i) / 10.0);
        if (i > 0) d = min(d, sdRoundCone(q, float3(prev, 0), float3(pt, 0), rPrev, r));
        prev = pt;
        rPrev = r;
    }
    return d;
}

ORB_FORMA(luna)
