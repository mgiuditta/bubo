#include "../OrbShading.h"

// Codice: a pair of curly brackets, one bent tube folded into four.
static float parentesi(float3 p, float) {
    float2 q = float2(-abs(p.x), abs(p.y));            // the upper half of the left bracket
    const float x = -0.40, top = 0.80, a = 0.22;
    float hook = udQuarterArc(q, float2(x + a, top - a), a, float2(-1, 1));
    float stem = udSegment2(q, float2(x, top - a), float2(x, a));
    float cusp = udQuarterArc(q, float2(x - a, a), a, float2(1, -1));
    return length(float2(min(hook, min(stem, cusp)), p.z)) - 0.085;
}

ORB_FORMA(parentesi)
