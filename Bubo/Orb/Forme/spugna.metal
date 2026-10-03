#include "../OrbShading.h"

// Chat: a kitchen sponge seen from above and a little in front: a thick soft layer under a narrower scouring layer,
// with three bumps on top.
static float spugna(float3 p, float) {
    p.yz = p.yz * rot(-0.5);
    float soft = sdRoundBox(p - float3(0, -0.12, 0), float3(0.72, 0.2, 0.4), 0.1);
    float rough = sdRoundBox(p - float3(0, 0.2, 0), float3(0.64, 0.12, 0.34), 0.1);
    float bumps = min(length(p - float3(-0.3, 0.36, 0.1)) - 0.07, min(length(p - float3(0.1, 0.36, -0.15)) - 0.07, length(p - float3(0.35, 0.36, 0.15)) - 0.07));
    return min(soft, min(rough, bumps));
}

ORB_FORMA(spugna)
