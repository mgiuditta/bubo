#include "../OrbShading.h"

// Tempo · autunno: a pumpkin, five fat segments side by side and a bent stem.
static float zucca(float3 p, float) {
    const float xs[5] = { -0.55, -0.28, 0.0, 0.28, 0.55 };
    const float rs[5] = { 0.40, 0.50, 0.54, 0.50, 0.40 };
    float d = sdRoundCone(p, float3(0, 0.34, 0), float3(0.12, 0.72, 0), 0.11, 0.07);
    for (int i = 0; i < 5; i++) d = min(d, length(p - float3(xs[i], -0.15, 0)) - rs[i]);
    return d;
}

ORB_FORMA(zucca)
