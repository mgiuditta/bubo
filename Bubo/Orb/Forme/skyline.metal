#include "../OrbShading.h"

// Viaggi: a city skyline, three skyscrapers of different heights on a low slab, the tallest with an antenna.
static float skyline(float3 p, float) {
    p.y += 0.15;
    float left = sdRoundBox(p - float3(-0.52, -0.25, 0), float3(0.26, 0.45, 0.2), 0.02);
    float middle = sdRoundBox(p - float3(0, 0.1, 0), float3(0.26, 0.8, 0.2), 0.02);
    float right = sdRoundBox(p - float3(0.52, -0.1, 0), float3(0.26, 0.6, 0.2), 0.02);
    float slab = sdRoundBox(p - float3(0, -0.72, 0), float3(0.9, 0.04, 0.25), 0.02);
    float antenna = sdSegment(p, float3(0, 0.9, 0), float3(0, 1.1, 0), 0.03);
    return min(min(left, middle), min(right, min(slab, antenna)));
}

ORB_FORMA(skyline)
