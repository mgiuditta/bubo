#include "../OrbShading.h"

// Chat · casa: a beer mug with a handle and a head of foam that swells and settles over the rim.
static float boccale(float3 p, float t) {
    float mug = sdRoundBox(p - float3(-0.1, -0.12, 0), float3(0.34, 0.5, 0.3), 0.1);
    float handle = sdTorusXY(p - float3(0.36, -0.12, 0), 0.2, 0.055);
    float rise = 0.02 + 0.025 * sin(t * 1.4);
    float foam = min(min(length(p - float3(-0.28, 0.4 + rise, 0)) - 0.17, length(p - float3(-0.08, 0.46 + rise * 1.4, 0)) - 0.2),
                     length(p - float3(0.1, 0.4 + rise * 0.6, 0)) - 0.15);
    float drip = length(p - float3(0.2, 0.34 - 0.07 * (0.5 + 0.5 * sin(t * 1.4 - 0.8)), 0.24)) - 0.06;
    return min(min(mug, handle), min(foam, drip));
}

ORB_FORMA(boccale)
