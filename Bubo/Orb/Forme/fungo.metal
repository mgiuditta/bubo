#include "../OrbShading.h"

// Chat · funghi: a mushroom, a domed cap of three rounded steps with two spots on a thick stem.
static float fungo(float3 p, float) {
    float stem = sdRoundCone(p, float3(0, -0.72, 0), float3(0, -0.05, 0), 0.17, 0.12);
    float c1 = sdCappedCone(p - float3(0, 0.07, 0), 0.09, 0.62, 0.52) - 0.03;
    float c2 = sdCappedCone(p - float3(0, 0.30, 0), 0.14, 0.52, 0.36) - 0.03;
    float c3 = sdCappedCone(p - float3(0, 0.56, 0), 0.10, 0.36, 0.14) - 0.03;
    float spots = min(length(p - float3(-0.22, 0.28, 0.38)) - 0.07, length(p - float3(0.25, 0.40, 0.29)) - 0.06);
    return min(min(stem, c1), min(min(c2, c3), spots));
}

ORB_FORMA(fungo)
