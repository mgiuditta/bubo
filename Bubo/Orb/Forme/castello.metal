#include "../OrbShading.h"

// Viaggi · monumenti: a castle, a wall between three crenellated towers, the middle one taller.
static float castello(float3 p, float) {
    float d = sdRoundBox2(p.xy - float2(0, -0.45), float2(0.80, 0.30), 0.03);
    d = min(d, sdRoundBox2(p.xy - float2(0, 0.20), float2(0.20, 0.55), 0.03));
    d = min(d, sdRoundBox2(float2(abs(p.x) - 0.62, p.y), float2(0.20, 0.35), 0.03));
    for (int i = 0; i < 2; i++) {
        float side = i == 0 ? -1.0 : 1.0;
        d = min(d, sdRoundBox2(p.xy - float2(0.14 * side, 0.81), float2(0.06), 0.02));
        d = min(d, sdRoundBox2(p.xy - float2(0.76 * side, 0.41), float2(0.06), 0.02));
        d = min(d, sdRoundBox2(p.xy - float2(0.48 * side, 0.41), float2(0.06), 0.02));
    }
    return extrude(d, p.z, 0.06) - 0.03;
}

ORB_FORMA(castello)
