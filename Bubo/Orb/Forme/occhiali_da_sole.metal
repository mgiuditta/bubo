#include "../OrbShading.h"

// Meteo: a pair of sunglasses with squared dark lenses, a bridge and the arms going back.
static float occhiali_da_sole(float3 p, float) {
    float3 m = float3(abs(p.x), p.y, p.z);
    float lens = extrude(sdRoundBox2(m.xy - float2(0.42, 0), float2(0.34, 0.26), 0.1), m.z, 0.05) - 0.04;
    float bridge = min(sdSegment(p, float3(-0.1, 0.08, 0), float3(0, 0.14, 0), 0.05),
                       sdSegment(p, float3(0, 0.14, 0), float3(0.1, 0.08, 0), 0.05));
    float arm = sdSegment(m, float3(0.76, 0.2, 0), float3(0.9, 0.2, -0.55), 0.045);
    return min(lens, min(bridge, arm));
}

ORB_FORMA(occhiali_da_sole)
