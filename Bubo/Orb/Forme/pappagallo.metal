#include "../OrbShading.h"

// Chat · natura: a parrot in profile on a branch, hooked beak and long tail.
static float pappagallo(float3 p, float) {
    p.y -= 0.14;
    float body = sdRoundCone(p, float3(0, -0.35, 0), float3(0, 0.15, 0), 0.2, 0.26);
    float head = length(p - float3(0.02, 0.4, 0)) - 0.22;
    float beak = min(sdRoundCone(p, float3(0.16, 0.43, 0), float3(0.38, 0.36, 0), 0.1, 0.04),
                     sdSegment(p, float3(0.38, 0.36, 0), float3(0.36, 0.22, 0), 0.04));
    float tail = sdRoundCone(p, float3(-0.02, -0.45, 0), float3(-0.24, -0.9, 0), 0.12, 0.05);
    float wing = sdSegment(p, float3(-0.12, 0.05, 0.15), float3(-0.16, -0.45, 0.15), 0.1);
    float branch = sdSegment(p, float3(-0.6, -0.5, 0), float3(0.6, -0.58, 0), 0.06);
    return min(min(min(body, head), min(beak, tail)), min(wing, branch));
}

ORB_FORMA(pappagallo)
