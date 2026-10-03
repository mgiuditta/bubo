#include "../OrbShading.h"

// Codice · verifica: a test tube half full, with a flared lip; a bubble rises through the liquid and out of it.
static float provetta(float3 p, float t) {
    p.xy = p.xy * rot(-0.22);
    p.y -= 0.04;
    const float r = 0.21;
    float liquid = min(sdCylinder(p - float3(0, -0.24, 0), r, 0.22), length(p - float3(0, -0.46, 0)) - r);
    float3 q = float3(abs(p.x), p.y, p.z);
    float wall = sdSegment(q, float3(r + 0.01, -0.02, 0), float3(r + 0.01, 0.68, 0), 0.035);
    float lip = length(float2(length(p.xz) - (r + 0.06), p.y - 0.72)) - 0.05;
    float rise = fract(t / 2.6);
    float bubble = length(p - float3(0.02, -0.56 + 0.90 * rise, 0.17)) - 0.065;
    return min(min(liquid, wall), min(lip, bubble));
}

ORB_FORMA(provetta)
