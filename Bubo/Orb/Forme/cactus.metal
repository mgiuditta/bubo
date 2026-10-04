#include "../OrbShading.h"

// Viaggi: a cactus with a trunk and two arms, a flower on top, in a pot.
static float cactus(float3 p, float) {
    float trunk = sdSegment(p, float3(0, -0.85, 0), float3(0, 0.6, 0), 0.22);
    float left = min(sdSegment(p, float3(-0.15, -0.1, 0), float3(-0.5, -0.1, 0), 0.13), sdSegment(p, float3(-0.5, -0.1, 0), float3(-0.5, 0.3, 0), 0.13));
    float right = min(sdSegment(p, float3(0.15, -0.3, 0), float3(0.5, -0.3, 0), 0.13), sdSegment(p, float3(0.5, -0.3, 0), float3(0.5, 0.1, 0), 0.13));
    float pot = sdCylinder(p - float3(0, -0.78, 0), 0.38, 0.14);
    float flower = length(p - float3(0, 0.9, 0)) - 0.09;
    return min(min(trunk, pot), min(min(left, right), flower));
}

ORB_FORMA(cactus)
