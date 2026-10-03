#include "../OrbShading.h"

// Salute: a plaster, two strips crossed in an X with a padded square at the crossing.
static float cerotto(float3 p, float) {
    float d = 9.0;
    for (int i = 0; i < 2; i++) {
        float2 l = p.xy * rot(i == 0 ? 0.7 : -0.7);
        d = min(d, sdRoundBox(float3(l, p.z), float3(0.95, 0.20, 0.04), 0.04));
    }
    float pad = sdRoundBox(p - float3(0, 0, 0.03), float3(0.26, 0.26, 0.06), 0.06);
    return min(d, pad);
}

ORB_FORMA(cerotto)
