#include "../OrbShading.h"

// Creativo: a classical bust on its base, head, neck, shoulders and chest, with the nose standing out.
static float busto(float3 p, float) {
    float head = sdRoundCone(p, float3(0, 0.38, 0), float3(0, 0.62, 0), 0.25, 0.3);
    float nose = length(p - float3(0, 0.48, 0.3)) - 0.07;
    float neck = sdCylinder(p - float3(0, 0.08, 0), 0.14, 0.12);
    float shoulders = sdSegment(p, float3(-0.42, -0.12, 0), float3(0.42, -0.12, 0), 0.2);
    float chest = sdRoundBox(p - float3(0, -0.38, 0), float3(0.36, 0.24, 0.18), 0.12);
    float base = sdRoundBox(p - float3(0, -0.75, 0), float3(0.45, 0.13, 0.3), 0.03);
    return min(min(head, nose), min(min(neck, shoulders), min(chest, base)));
}

ORB_FORMA(busto)
