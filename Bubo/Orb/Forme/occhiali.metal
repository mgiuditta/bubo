#include "../OrbShading.h"

// Codice · revisione: round glasses with a thin bridge and the two temples running back.
static float occhiali(float3 p, float) {
    float3 q = float3(abs(p.x), p.y, p.z);
    float rim = sdTorusXY(q - float3(0.40, 0, 0), 0.28, 0.055);
    float bridge = sdSegment(q, float3(0.10, 0.12, 0), float3(0, 0.15, 0), 0.04);
    float temple = sdSegment(q, float3(0.68, 0.10, 0), float3(0.82, 0.12, -0.5), 0.04);
    return min(min(rim, bridge), temple);
}

ORB_FORMA(occhiali)
