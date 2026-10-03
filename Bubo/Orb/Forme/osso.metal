#include "../OrbShading.h"

// Salute · ossa e articolazioni: a bone on the diagonal, two round knobs at each end.
static float osso(float3 p, float) {
    float shaft = sdSegment(p, float3(-0.5, -0.5, 0), float3(0.5, 0.5, 0), 0.14);
    float up = min(length(p - float3(0.479, 0.621, 0)) - 0.19, length(p - float3(0.621, 0.479, 0)) - 0.19);
    float down = min(length(p - float3(-0.479, -0.621, 0)) - 0.19, length(p - float3(-0.621, -0.479, 0)) - 0.19);
    return min(shaft, min(up, down));
}

ORB_FORMA(osso)
