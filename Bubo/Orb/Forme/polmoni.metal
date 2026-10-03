#include "../OrbShading.h"

// Salute · respiro: two lungs with the windpipe and its two bronchi; the lungs swell and shrink.
static float polmoni(float3 p, float t) {
    float s = 1.0 + 0.07 * sin(t * 1.6);
    float3 q = float3(abs(p.x), p.y, p.z) / s;
    float lungs = sdRoundCone(q, float3(0.45, -0.2, 0), float3(0.35, 0.3, 0), 0.40, 0.22) * s;
    float trachea = sdSegment(p, float3(0, 0.9, 0), float3(0, 0.35, 0), 0.07);
    float bronchi = sdSegment(float3(abs(p.x), p.y, p.z), float3(0, 0.35, 0), float3(0.2, 0.1, 0), 0.05);
    return min(lungs, min(trachea, bronchi));
}

ORB_FORMA(polmoni)
