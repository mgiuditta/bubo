#include "../OrbShading.h"

// Salute: a straight comb, a thick spine over eleven close teeth.
static float pettine(float3 p, float) {
    float d = sdRoundBox(p - float3(0, 0.4, 0), float3(0.78, 0.15, 0.08), 0.06);
    for (int i = 0; i < 11; i++) {
        d = min(d, sdRoundBox(p - float3(-0.7 + 0.14 * float(i), -0.1, 0), float3(0.04, 0.42, 0.05), 0.03));
    }
    return d;
}

ORB_FORMA(pettine)
