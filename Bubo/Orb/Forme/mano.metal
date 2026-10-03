#include "../OrbShading.h"

// Agente: an open hand raised, palm to the viewer: a palm, four fingers and a thumb.
static float mano(float3 p, float) {
    p.xy += float2(-0.20, 0.10);
    float2 q = p.xy;
    float d = sdRoundBox2(q - float2(0.0, -0.30), float2(0.37, 0.28), 0.10);
    const float tops[4] = { 0.50, 0.70, 0.64, 0.46 };
    for (int i = 0; i < 4; i++) {
        float x = -0.30 + 0.20 * float(i);
        d = min(d, udSegment2(q, float2(x, -0.05), float2(x, tops[i])) - 0.07);
    }
    d = min(d, udSegment2(q, float2(-0.36, -0.42), float2(-0.72, -0.02)) - 0.085);
    return extrude(d, p.z, 0.07) - 0.01;
}

ORB_FORMA(mano)
