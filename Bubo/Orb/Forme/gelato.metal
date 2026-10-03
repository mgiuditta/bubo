#include "../OrbShading.h"

// Chat · casa: an ice-cream cone, point down, with two scoops.
static float gelato(float3 p, float) {
    float cone = sdCappedCone(p - float3(0, -0.46, 0), 0.40, 0.03, 0.30);
    float low = length(p - float3(0, -0.02, 0)) - 0.34;
    float high = length(p - float3(0.03, 0.50, 0)) - 0.28;
    return min(cone, min(low, high));
}

ORB_FORMA(gelato)
