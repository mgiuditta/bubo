#include "../OrbShading.h"

// A pawn standing on y = 0, about 0.74 tall: a base, a tapering stem, a collar and a round head.
static float pedineOne(float3 p) {
    float base = sdCylinder(p - float3(0, 0.05, 0), 0.22, 0.05);
    float stem = sdCappedCone(p - float3(0, 0.3, 0), 0.2, 0.16, 0.08);
    float collar = sdCylinder(p - float3(0, 0.5, 0), 0.14, 0.025);
    float head = length(p - float3(0, 0.6, 0)) - 0.14;
    return min(min(base, stem), min(collar, head));
}

// Agente: three pawns grouped, the middle one taller.
static float pedine(float3 p, float) {
    float left = pedineOne((p - float3(-0.5, -0.65, 0)) / 1.2) * 1.2;
    float middle = pedineOne((p - float3(0, -0.65, 0)) / 1.65) * 1.65;
    float right = pedineOne((p - float3(0.5, -0.65, 0)) / 1.2) * 1.2;
    return min(left, min(middle, right));
}

ORB_FORMA(pedine)
