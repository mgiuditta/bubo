#include "../OrbShading.h"

// One burst around the origin, about 0.47 wide: a core, eight rays and a spark at the end of each.
static float fuochiBurst(float3 q) {
    float2 r = q.xy;
    float d = length(r) - 0.07;
    for (int i = 0; i < 8; i++) {
        float a = float(i) * M_PI_F * 0.25;
        float2 dir = float2(cos(a), sin(a));
        d = min(d, udSegment2(r, dir * 0.14, dir * 0.30) - 0.03);
        d = min(d, length(r - dir * 0.40) - 0.05);
    }
    return extrude(d, q.z, 0.02) - 0.02;
}

// Tempo: three fireworks bursting, each opening and closing on its own beat (uniform scale about its centre).
static float fuochi_artificio(float3 p, float t) {
    const float2 centres[3] = { float2(-0.50, 0.40), float2(0.50, 0.40), float2(0.0, -0.45) };
    float d = 1e3;
    for (int k = 0; k < 3; k++) {
        float s = 0.7 + 0.3 * sin(t * 1.8 + 2.1 * float(k));
        d = min(d, fuochiBurst((p - float3(centres[k], 0)) / s) * s);
    }
    return d;
}

ORB_FORMA(fuochi_artificio)
