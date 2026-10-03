#include "../OrbShading.h"

// Codice · scrittura: a lowercase i in relief on a round plate.
static float info(float3 p, float) {
    float plate = extrude(length(p.xy) - 0.7, p.z, 0.08) - 0.1;
    float dotOfI = length(p - float3(0, 0.4, 0.26)) - 0.1;
    float stem = sdRoundBox(p - float3(0, -0.12, 0.22), float3(0.07, 0.27, 0.05), 0.03);
    float foot = sdRoundBox(p - float3(0, -0.37, 0.22), float3(0.17, 0.04, 0.05), 0.03);
    float head = sdRoundBox(p - float3(-0.08, 0.1, 0.22), float3(0.14, 0.04, 0.05), 0.03);
    return min(min(plate, dotOfI), min(stem, min(foot, head)));
}

ORB_FORMA(info)
