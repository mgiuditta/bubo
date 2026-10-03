#include "../OrbShading.h"

// Codice · dipendenze: an org chart, one square on top joined to three squares below.
static float gerarchia(float3 p, float) {
    float d = sdRoundBox2(p.xy - float2(0, 0.55), float2(0.17), 0.04);
    for (int i = -1; i <= 1; i++) {
        float x = 0.6 * float(i);
        d = min(d, sdRoundBox2(p.xy - float2(x, -0.55), float2(0.15), 0.04));
        d = min(d, udSegment2(p.xy, float2(x, 0.0), float2(x, -0.40)) - 0.035);
    }
    d = min(d, udSegment2(p.xy, float2(0, 0.40), float2(0, 0.0)) - 0.035);
    d = min(d, udSegment2(p.xy, float2(-0.6, 0.0), float2(0.6, 0.0)) - 0.035);
    return extrude(d, p.z, 0.05) - 0.03;
}

ORB_FORMA(gerarchia)
