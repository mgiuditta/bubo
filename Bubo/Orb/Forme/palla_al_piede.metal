#include "../OrbShading.h"

// Finanza: a ball and chain, the chain of four links leading to the shackle ring.
static float palla_al_piede(float3 p, float) {
    float ball = length(p - float3(-0.3, -0.4, 0)) - 0.42;
    float ring = sdTorusXY(p - float3(0.55, 0.5, 0), 0.28, 0.06);
    float d = min(ball, ring);
    const float2 dir = normalize(float2(0.8, 0.9));
    const float2 start = float2(-0.02, -0.085);
    for (int i = 0; i < 4; i++) {
        float2 c = start + dir * (0.06 + 0.13 * float(i));
        float3 q = p - float3(c, 0);
        q.xy = q.xy * rot(-atan2(dir.y, dir.x));
        d = min(d, (i % 2 == 0) ? sdTorusXY(q, 0.085, 0.035) : sdTorusXY(q.xzy, 0.085, 0.035));
    }
    return d;
}

ORB_FORMA(palla_al_piede)
