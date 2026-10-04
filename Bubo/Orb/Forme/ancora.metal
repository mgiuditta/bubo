#include "../OrbShading.h"

// Codice · rilascio: an anchor, a ring on top, a shaft with its stock and the two curved arms with their flukes.
static float ancora(float3 p, float) {
    float2 q = float2(abs(p.x), p.y);
    float d2 = abs(length(p.xy - float2(0, 0.76)) - 0.12);
    d2 = min(d2, udSegment2(p.xy, float2(0, 0.64), float2(0, -0.6)));
    d2 = min(d2, udSegment2(q, float2(0, 0.42), float2(0.3, 0.42)));
    d2 = min(d2, udQuarterArc(q, float2(0, -0.1), 0.5, float2(1, -1)));
    d2 = min(d2, udSegment2(q, float2(0.5, -0.1), float2(0.72, 0.1)));
    float stroke = d2 - 0.055;
    float fluke = length(q - float2(0.72, 0.1)) - 0.1;
    return extrude(min(stroke, fluke), p.z, 0.05);
}

ORB_FORMA(ancora)
