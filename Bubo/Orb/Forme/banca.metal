#include "../OrbShading.h"

// Finanza · banche: a bank, a pediment over four columns on two steps.
static float banca(float3 p, float) {
    float d = sdQuad2(p.xy, float2(-0.85, 0.36), float2(0, 0.36), float2(0.85, 0.36), float2(0, 0.88));
    d = min(d, sdRoundBox2(p.xy - float2(0, 0.30), float2(0.80, 0.06), 0.02));
    for (int i = 0; i < 4; i++) {
        float x = -0.6 + 0.4 * float(i);
        d = min(d, sdRoundBox2(p.xy - float2(x, -0.10), float2(0.08, 0.30), 0.02));
    }
    d = min(d, sdRoundBox2(p.xy - float2(0, -0.50), float2(0.80, 0.06), 0.02));
    d = min(d, sdRoundBox2(p.xy - float2(0, -0.68), float2(0.90, 0.07), 0.02));
    return extrude(d, p.z, 0.06) - 0.03;
}

ORB_FORMA(banca)
