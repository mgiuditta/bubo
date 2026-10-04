#include "../OrbShading.h"

// Salute · corpo: an ear in profile, an open outer rim with its lobe, an inner curl and the canal in the middle.
static float orecchio(float3 p, float) {
    float2 o = p.xy - float2(-0.05, 0.1);
    float outer = min(udQuarterArc(o, float2(0), 0.6, float2(-1, 1)),
                      min(udQuarterArc(o, float2(0), 0.6, float2(-1, -1)), udQuarterArc(o, float2(0), 0.6, float2(1, 1)))) - 0.07;
    float2 n = p.xy - float2(-0.05, 0.12);
    float inner = min(udQuarterArc(n, float2(0), 0.3, float2(1, 1)),
                      min(udQuarterArc(n, float2(0), 0.3, float2(-1, 1)), udQuarterArc(n, float2(0), 0.3, float2(-1, -1)))) - 0.06;
    float lobe = length(p.xy - float2(0, -0.55)) - 0.14;
    float canal = length(p.xy - float2(0.05, -0.05)) - 0.1;
    return extrude(min(min(outer, inner), min(lobe, canal)), p.z, 0.05);
}

ORB_FORMA(orecchio)
