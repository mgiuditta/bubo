#include "../OrbShading.h"

// Ricerca: a magnifying glass: ring, glass (a thin disc) and handle.
static float lente(float3 p, float) {
    const float scale = 1.2;                           // uniform scale keeps the SDF exact
    p /= scale;
    float3 c = float3(-0.14, 0.16, 0);
    float3 q = p - c;
    float ring = length(float2(length(q.xy) - 0.40, q.z)) - 0.08;
    float glass = extrude(length(q.xy) - 0.36, q.z, 0.015);
    float handle = sdSegment(p, c + float3(0.34, -0.34, 0), float3(0.62, -0.64, 0), 0.10);
    return min(min(ring, glass), handle) * scale;
}

ORB_FORMA(lente)
