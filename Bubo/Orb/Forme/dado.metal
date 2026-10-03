#include "../OrbShading.h"

// Chat · giochi da tavolo: a die with rounded corners and pips; it tumbles once and comes to rest.
static float dado(float3 p, float t) {
    float e = clamp(fract(t / 5.0) / 0.45, 0.0, 1.0);
    float a = 6.2832 * (1.0 - (1.0 - e) * (1.0 - e) * (1.0 - e));
    p.xy = p.xy * rot(a);
    p.yz = p.yz * rot(a);
    p.xz = p.xz * rot(0.6);
    p.yz = p.yz * rot(0.4);
    float d = sdRoundBox(p, float3(0.38), 0.10);
    d = min(d, length(p - float3(0, 0, 0.38)) - 0.06);
    for (int i = 0; i < 4; i++) {
        float2 c = 0.2 * float2(i % 2 == 0 ? -1.0 : 1.0, i < 2 ? -1.0 : 1.0);
        d = min(d, length(p - float3(c, 0.38)) - 0.06);
    }
    d = min(d, length(p - float3(-0.2, 0.38, -0.2)) - 0.06);
    d = min(d, length(p - float3(0, 0.38, 0)) - 0.06);
    d = min(d, length(p - float3(0.2, 0.38, 0.2)) - 0.06);
    d = min(d, length(p - float3(0.38, -0.18, 0.18)) - 0.06);
    return min(d, length(p - float3(0.38, 0.18, -0.18)) - 0.06);
}

ORB_FORMA(dado)
