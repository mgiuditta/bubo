#include "../OrbShading.h"

// Salute · latticini: a milk carton, a tall box with the pitched roof and the ridge on top.
static float cartone_latte(float3 p, float) {
    float d = sdRoundBox2(p.xy - float2(0, -0.25), float2(0.38, 0.55), 0.02);
    d = min(d, sdQuad2(p.xy, float2(-0.38, 0.30), float2(0, 0.30), float2(0.38, 0.30), float2(0, 0.78)));
    d = min(d, sdRoundBox2(p.xy - float2(0, 0.80), float2(0.12, 0.04), 0.02));
    return extrude(d, p.z, 0.22) - 0.03;
}

ORB_FORMA(cartone_latte)
