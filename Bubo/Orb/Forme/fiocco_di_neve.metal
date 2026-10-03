#include "../OrbShading.h"

// Meteo: a snowflake, six arms with two pairs of branches each, turning slowly.
static float fiocco_di_neve(float3 p, float t) {
    float2 xy = p.xy * rot(-t * 0.3);
    float d = 9.0;
    for (int i = 0; i < 6; i++) {
        float2 a = xy * rot(-1.0471976 * float(i));
        float3 q = float3(abs(a.x), a.y, p.z);
        d = min(d, sdSegment(q, float3(0, 0, 0), float3(0, 0.85, 0), 0.04));
        d = min(d, sdSegment(q, float3(0, 0.55, 0), float3(0.20, 0.75, 0), 0.035));
        d = min(d, sdSegment(q, float3(0, 0.32, 0), float3(0.14, 0.46, 0), 0.035));
    }
    return d;
}

ORB_FORMA(fiocco_di_neve)
