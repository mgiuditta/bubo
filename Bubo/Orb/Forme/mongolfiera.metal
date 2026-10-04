#include "../OrbShading.h"

// Viaggi: a hot-air balloon with its basket and ropes, bobbing slowly up and down.
static float mongolfiera(float3 p, float t) {
    p.y -= 0.05 * sin(t * 0.9);
    float envelope = sdRoundCone(p, float3(0, 0.35, 0), float3(0, -0.30, 0), 0.55, 0.12);
    float basket = sdRoundBox(p - float3(0, -0.78, 0), float3(0.13, 0.09, 0.13), 0.03);
    float ropes = sdSegment(p, float3(-0.09, -0.34, 0), float3(-0.11, -0.69, 0), 0.02);
    ropes = min(ropes, sdSegment(p, float3(0.09, -0.34, 0), float3(0.11, -0.69, 0), 0.02));
    return min(envelope, min(basket, ropes));
}

ORB_FORMA(mongolfiera)
