#include "../OrbShading.h"

// Distance to the right half of the circle of radius R around the origin.
static float microscopioArc(float2 q, float R) {
    return q.x >= 0.0 ? abs(length(q) - R) : min(length(q - float2(0, R)), length(q + float2(0, R)));
}

// Ricerca: a microscope: a tilted tube with its lens, a stage, a curved arm and a heavy base.
static float microscopio(float3 p, float) {
    float arm = length(float2(microscopioArc(p.xy - float2(0.10, -0.10), 0.55), p.z)) - 0.07;
    float tube = sdSegment(p, float3(-0.15, 0.80, 0), float3(0.0, 0.15, 0), 0.12);
    float lens = sdSegment(p, float3(0.0, 0.15, 0), float3(0.03, -0.08, 0), 0.06);
    float stage = sdRoundBox(p - float3(0.20, -0.32, 0), float3(0.40, 0.04, 0.15), 0.02);
    float base = sdRoundBox(p - float3(0, -0.78, 0), float3(0.62, 0.07, 0.25), 0.04);
    return min(min(arm, tube), min(lens, min(stage, base)));
}

ORB_FORMA(microscopio)
