#include "../OrbShading.h"

// Ricerca · un ago nel pagliaio: a domed haystack on the ground, a few straws sticking out of its top.
static float pagliaio(float3 p, float) {
    float stack = sdRoundCone(p, float3(0, -0.4, 0), float3(0, 0.3, 0), 0.5, 0.32);
    float ground = sdSegment(p, float3(-0.9, -0.9, 0), float3(0.9, -0.9, 0), 0.05);
    float straws = min(sdSegment(p, float3(0, 0.58, 0), float3(0, 0.9, 0), 0.035),
                       min(sdSegment(p, float3(-0.1, 0.56, 0), float3(-0.3, 0.82, 0), 0.035),
                           sdSegment(p, float3(0.1, 0.56, 0), float3(0.3, 0.82, 0), 0.035)));
    return min(stack, min(ground, straws));
}

ORB_FORMA(pagliaio)
