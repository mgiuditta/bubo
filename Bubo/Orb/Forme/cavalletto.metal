#include "../OrbShading.h"

// Creativo: a painter's easel: two front legs, a back leg, a crossbar and a canvas.
static float cavalletto(float3 p, float) {
    float canvas = sdRoundBox(p - float3(0, 0.2, 0.1), float3(0.40, 0.32, 0.03), 0.02);
    float legL = sdSegment(p, float3(0, 0.80, -0.05), float3(-0.55, -0.85, 0.05), 0.05);
    float legR = sdSegment(p, float3(0, 0.80, -0.05), float3(0.55, -0.85, 0.05), 0.05);
    float back = sdSegment(p, float3(0, 0.80, -0.05), float3(0, -0.85, -0.55), 0.05);
    float bar = sdSegment(p, float3(-0.40, -0.20, 0.06), float3(0.40, -0.20, 0.06), 0.045);
    return min(min(canvas, bar), min(legL, min(legR, back)));
}

ORB_FORMA(cavalletto)
