#include "../OrbShading.h"

// Codice · scrittura: a stylized person, arms and legs spread, inside a circle.
static float omino(float3 p, float) {
    float2 q = float2(abs(p.x), p.y);
    float d2 = abs(length(p.xy) - 0.8) - 0.06;
    d2 = min(d2, length(p.xy - float2(0, 0.4)) - 0.12);
    d2 = min(d2, udSegment2(q, float2(0, 0.22), float2(0.45, 0.22)) - 0.05);
    d2 = min(d2, udSegment2(q, float2(0, 0.22), float2(0, -0.1)) - 0.05);
    d2 = min(d2, udSegment2(q, float2(0, -0.1), float2(0.25, -0.55)) - 0.05);
    return extrude(d2, p.z, 0.05);
}

ORB_FORMA(omino)
