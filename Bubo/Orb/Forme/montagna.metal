#include "../OrbShading.h"

static float montagnaTriangle(float2 p, float2 a, float2 b, float2 c) {
    return sdQuad2(p, a, b, c, 0.5 * (c + a));
}

// Viaggi: a mountain with a smaller peak beside it and a snowy cap that stands out from the rock.
static float montagna(float3 p, float) {
    p.xy += float2(-0.10, 0.07);
    float2 q = p.xy;
    float rock = min(montagnaTriangle(q, float2(-0.10, 0.70), float2(-0.85, -0.55), float2(0.65, -0.55)),
                     montagnaTriangle(q, float2(0.50, 0.25), float2(0.15, -0.55), float2(0.68, -0.55)));
    float cap = montagnaTriangle(q, float2(-0.10, 0.70), float2(-0.37, 0.25), float2(0.17, 0.25));
    cap = min(cap, montagnaTriangle(q, float2(-0.37, 0.25), float2(-0.17, 0.25), float2(-0.27, 0.07)));
    cap = min(cap, montagnaTriangle(q, float2(-0.17, 0.25), float2(0.03, 0.25), float2(-0.07, 0.02)));
    cap = min(cap, montagnaTriangle(q, float2(0.03, 0.25), float2(0.17, 0.25), float2(0.10, 0.10)));
    return min(extrude(rock, p.z, 0.04) - 0.03, extrude(cap, p.z - 0.04, 0.06) - 0.03);
}

ORB_FORMA(montagna)
