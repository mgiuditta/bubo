#include "../OrbShading.h"

// Agente · giri a vuoto: a hamster wheel on its stand, turning round and round.
static float ruota_criceto(float3 p, float t) {
    const float3 hub = float3(0, 0.12, 0);
    float3 w = p - hub;
    float rings = min(sdTorusXY(w - float3(0, 0, 0.14), 0.58, 0.04), sdTorusXY(w + float3(0, 0, 0.14), 0.58, 0.04));
    float d = min(rings, sdSegment(w, float3(0, 0, -0.18), float3(0, 0, 0.18), 0.07));
    for (int i = 0; i < 8; i++) {
        float a = float(i) * M_PI_F / 4.0 + t * 0.8;
        float2 dir = float2(cos(a), sin(a));
        d = min(d, sdSegment(w, float3(dir * 0.58, -0.14), float3(dir * 0.58, 0.14), 0.03));
        if (i < 4) d = min(d, sdSegment(w, float3(dir * 0.07, 0.14), float3(dir * 0.55, 0.14), 0.025));
    }
    float stand = min(sdSegment(p, hub + float3(0, 0, 0.18), float3(-0.5, -0.9, 0.18), 0.05),
                      sdSegment(p, hub + float3(0, 0, 0.18), float3(0.5, -0.9, 0.18), 0.05));
    float base = sdSegment(p, float3(-0.6, -0.92, 0.18), float3(0.6, -0.92, 0.18), 0.06);
    return min(d, min(stand, base));
}

ORB_FORMA(ruota_criceto)
