#include "../OrbShading.h"

// Chat · conversazione: a big rounded question mark, tilting now and then like someone wondering.
static float punto_interrogativo(float3 p, float t) {
    const float2 pivot = float2(0, -0.58);
    p.xy = (p.xy - pivot) * rot(0.16 * sin(t * 1.1)) + pivot;
    const float2 c = float2(0, 0.36);
    const float R = 0.30;
    float hook = min(min(udQuarterArc(p.xy, c, R, float2(-1, 1)), udQuarterArc(p.xy, c, R, float2(1, 1))),
                     udQuarterArc(p.xy, c, R, float2(1, -1)));
    float stem = udSegment2(p.xy, c - float2(0, R), float2(0, -0.20));
    float curve = length(float2(min(hook, stem), p.z)) - 0.115;
    return min(curve, length(p - float3(pivot, 0)) - 0.14);
}

ORB_FORMA(punto_interrogativo)
