#include "../OrbShading.h"

// Codice · nuovo progetto: a sprout, two round leaves on a short stem; the leaves open and close a little.
static float germoglio(float3 p, float t) {
    const float3 top = float3(0, -0.05, 0);
    float d = sdSegment(p, float3(0, -0.82, 0), top, 0.06);
    d = min(d, sdSegment(p, float3(-0.30, -0.84, 0), float3(0.30, -0.84, 0), 0.05));
    float a = 0.75 + 0.2 * sin(t * 0.9);
    float3 tip = 0.55 * float3(sin(a), cos(a), 0);
    float3 q = float3(abs(p.x), p.y, p.z);
    return min(d, sdRoundCone(q, top, top + tip, 0.05, 0.20));
}

ORB_FORMA(germoglio)
