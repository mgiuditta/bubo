#include "../OrbShading.h"

// Codice: a closed cardboard box turned to show two sides, a band of tape across the lid and down the front.
static float pacco(float3 p, float) {
    p.xz = p.xz * rot(0.5);
    p.yz = p.yz * rot(-0.3);
    float box = sdRoundBox(p, float3(0.50, 0.42, 0.42), 0.04);
    float tape = sdRoundBox(p, float3(0.09, 0.455, 0.455), 0.02);
    return min(box, tape);
}

ORB_FORMA(pacco)
