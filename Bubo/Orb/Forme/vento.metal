#include "../OrbShading.h"

// A curl to the right of c: the two quarter circles of radius R on that side.
static float ventoCurl(float2 q, float2 c, float R) {
    return min(udQuarterArc(q, c, R, float2(1, -1)), udQuarterArc(q, c, R, float2(1, 1)));
}

// Meteo: three wind lines, each with a curled end, drifting sideways at their own pace.
static float vento(float3 p, float t) {
    float2 a = p.xy - float2(0.08 * sin(t * 1.5), 0);
    float2 b = p.xy - float2(0.08 * sin(t * 1.5 + 2.1), 0);
    float2 c = p.xy - float2(0.08 * sin(t * 1.5 + 4.2), 0);
    float d = udSegment2(a, float2(-0.80, 0.50), float2(0.10, 0.50));
    d = min(d, ventoCurl(a, float2(0.10, 0.70), 0.20));
    d = min(d, udSegment2(b, float2(-0.60, 0.0), float2(0.45, 0.0)));
    d = min(d, ventoCurl(b, float2(0.45, -0.15), 0.15));
    d = min(d, udSegment2(c, float2(-0.80, -0.55), float2(0.0, -0.55)));
    d = min(d, ventoCurl(c, float2(0.0, -0.70), 0.15));
    return extrude(d - 0.05, p.z, 0.02) - 0.03;
}

ORB_FORMA(vento)
