#include "../OrbShading.h"

// One footprint with its big toe toward -x: a heel, a ball and five toes.
static float ormeFoot(float3 p) {
    float d = sdRoundCone(p, float3(0, -0.30, 0), float3(0, 0.06, 0), 0.10, 0.16);
    d = min(d, length(p - float3(-0.115, 0.28, 0)) - 0.065);
    const float2 toes[4] = { float2(-0.03, 0.33), float2(0.05, 0.32), float2(0.12, 0.28), float2(0.17, 0.22) };
    for (int i = 0; i < 4; i++) {
        d = min(d, length(p - float3(toes[i], 0)) - 0.05);
    }
    return d;
}

// Ricerca: two footprints, a left one behind and a right one ahead, a little turned.
static float orme(float3 p, float) {
    float3 l = p - float3(-0.30, -0.20, 0);
    l.xy = l.xy * rot(-0.12);
    l.x = -l.x;
    float3 r = p - float3(0.30, 0.25, 0);
    r.xy = r.xy * rot(0.10);
    return min(ormeFoot(l), ormeFoot(r));
}

ORB_FORMA(orme)
