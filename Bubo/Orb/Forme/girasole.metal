#include "../OrbShading.h"

// Chat · natura: a sunflower with its stem and two leaves; the head slowly turns.
static float girasole(float3 p, float t) {
    const float3 c = float3(0, 0.25, 0);
    float3 h = p - c;
    h.xy = h.xy * rot(-t * 0.4);
    float d = length(h) - 0.22;
    for (int i = 0; i < 12; i++) {
        float a = 0.5235988 * float(i);
        float2 dir = float2(cos(a), sin(a));
        d = min(d, sdRoundCone(h, float3(dir * 0.24, 0), float3(dir * 0.56, 0), 0.09, 0.03));
    }
    float stem = sdSegment(p, float3(0, 0.0, 0), float3(0, -0.85, 0), 0.05);
    float3 q = float3(abs(p.x), p.y, p.z);
    float leaf = sdRoundCone(q, float3(0.02, -0.55, 0), float3(0.40, -0.35, 0), 0.03, 0.12);
    return min(min(d, stem), leaf);
}

ORB_FORMA(girasole)
