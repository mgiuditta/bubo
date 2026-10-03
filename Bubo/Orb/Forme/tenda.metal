#include "../OrbShading.h"

static float tendaTriangle(float2 p, float2 a, float2 b, float2 c) {
    return sdQuad2(p, a, b, c, 0.5 * (c + a));
}

// Viaggi: a ridge tent seen from the front: two flaps pulled aside leave the entrance open, a groundline and a ridge pole on top.
static float tenda(float3 p, float) {
    float2 q = p.xy;
    float2 apex = float2(0, 0.70);
    float d = min(tendaTriangle(q, apex, float2(-0.85, -0.55), float2(-0.30, -0.55)),
                  tendaTriangle(q, apex, float2(0.30, -0.55), float2(0.85, -0.55)));
    d = min(d, udSegment2(q, float2(-0.85, -0.58), float2(0.85, -0.58)) - 0.04);
    d = min(d, udSegment2(q, apex, float2(0, 0.88)) - 0.03);
    return extrude(d, p.z, 0.03) - 0.03;
}

ORB_FORMA(tenda)
