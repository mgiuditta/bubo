#include "../OrbShading.h"

// Tempo · Natale: a Santa hat, the tip folded over and hanging with its pompom, which sways; a fluffy cuff.
static float cappello_natale(float3 p, float t) {
    float hat = sdRoundCone(p, float3(-0.1, -0.4, 0), float3(0.2, 0.45, 0), 0.5, 0.17);
    float fold = min(sdRoundCone(p, float3(0.2, 0.45, 0), float3(0.55, 0.35, 0), 0.17, 0.14),
                     sdRoundCone(p, float3(0.55, 0.35, 0), float3(0.7, 0.0, 0), 0.14, 0.10));
    float cuff = sdRoundBox(p - float3(0, -0.62, 0), float3(0.7, 0.16, 0.2), 0.12);
    float pompom = length(p - float3(0.74 + 0.07 * sin(t * 2.5), -0.18, 0)) - 0.17;
    return min(min(hat, fold), min(cuff, pompom));
}

ORB_FORMA(cappello_natale)
