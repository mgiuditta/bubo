#include "../OrbShading.h"

// Ricerca · classifica: a podium of three steps, the tallest in the middle, with a star over the winner.
static float podio(float3 p, float) {
    float d = sdRoundBox2(p.xy - float2(0, -0.10), float2(0.25, 0.60), 0.03);
    d = min(d, sdRoundBox2(p.xy - float2(-0.52, -0.35), float2(0.25, 0.35), 0.03));
    d = min(d, sdRoundBox2(p.xy - float2(0.52, -0.475), float2(0.25, 0.225), 0.03));
    d = min(d, sdStar5(p.xy - float2(0, 0.80), 0.22, 0.45));
    return extrude(d, p.z, 0.06) - 0.03;
}

ORB_FORMA(podio)
