#include "../OrbShading.h"

// Salute: a carrot with its leaves, lying diagonal.
static float carota(float3 p, float) {
    p.xy = p.xy * rot(0.6);
    p.y += 0.08;
    float root = sdRoundCone(p, float3(0, 0.35, 0), float3(0, -0.75, 0), 0.28, 0.04);
    float leaves = sdSegment(p, float3(0, 0.55, 0), float3(-0.25, 0.95, 0), 0.05);
    leaves = min(leaves, sdSegment(p, float3(0, 0.55, 0), float3(0, 1.0, 0), 0.05));
    leaves = min(leaves, sdSegment(p, float3(0, 0.55, 0), float3(0.25, 0.95, 0), 0.05));
    return min(root, leaves);
}

ORB_FORMA(carota)
