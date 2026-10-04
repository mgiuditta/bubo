#include "../OrbShading.h"

// Salute · calma: a lotus of five petals fanning from one base; the petals open and close slowly.
static float loto(float3 p, float t) {
    const float base = -0.70;
    float k = 1.0 + 0.12 * sin(t * 0.7);
    float d = 1e3;
    for (int i = -2; i <= 2; i++) {
        float a = 0.5 * float(i) * k;
        float len = i == 0 ? 1.35 : (abs(i) == 1 ? 1.25 : 1.0);
        float2 dir = float2(sin(a), cos(a));
        float3 from = float3(0, base, 0), to = float3(len * dir + float2(0, base), 0);
        d = min(d, sdRoundCone(p, from, to, 0.07, 0.03));
        d = min(d, length(p - float3(0.45 * len * dir + float2(0, base), 0)) - 0.19);
    }
    return d;
}

ORB_FORMA(loto)
