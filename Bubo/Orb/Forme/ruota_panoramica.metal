#include "../OrbShading.h"

// Viaggi: a Ferris wheel, a ring with six spokes and six cabins that stay upright, on an A-frame; it turns slowly.
static float ruota_panoramica(float3 p, float t) {
    float3 q = p - float3(0, 0.1, 0);
    float d = min(sdTorusXY(q, 0.62, 0.03), length(q) - 0.08);
    float3 f = float3(abs(p.x), p.y, p.z);
    d = min(d, sdSegment(f, float3(0, 0.1, 0), float3(0.42, -0.9, 0), 0.04));
    d = min(d, sdSegment(p, float3(-0.5, -0.93, 0), float3(0.5, -0.93, 0), 0.035));
    for (int i = 0; i < 6; i++) {
        float a = t * 0.3 + float(i) * 1.0472;
        float2 rim = 0.62 * float2(cos(a), sin(a));
        d = min(d, sdSegment(q, float3(0), float3(rim, 0), 0.02));
        d = min(d, sdSegment(q, float3(rim, 0), float3(rim.x, rim.y - 0.08, 0), 0.015));
        d = min(d, sdRoundBox(q - float3(rim.x, rim.y - 0.12, 0), float3(0.09, 0.07, 0.07), 0.04));
    }
    return d;
}

ORB_FORMA(ruota_panoramica)
