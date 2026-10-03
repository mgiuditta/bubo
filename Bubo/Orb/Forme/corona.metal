#include "../OrbShading.h"

static float coronaTri(float2 p, float2 a, float2 b, float2 c) {
    return sdQuad2(p, a, b, c, 0.5 * (c + a));
}

// Chat: a crown with three points and a plain band, no pearls.
static float corona(float3 p, float) {
    float2 q = p.xy;
    float points = min(coronaTri(q, float2(-0.65, -0.2), float2(-0.55, 0.5), float2(-0.1, -0.2)),
                       min(coronaTri(q, float2(-0.3, -0.2), float2(0, 0.7), float2(0.3, -0.2)),
                           coronaTri(q, float2(0.1, -0.2), float2(0.55, 0.5), float2(0.65, -0.2))));
    float band = sdRoundBox2(q - float2(0, -0.4), float2(0.68, 0.13), 0.04);
    return extrude(min(points, band), p.z, 0.1) - 0.04;
}

ORB_FORMA(corona)
