#include "../OrbShading.h"

// A signpost arrow pointing right: a board with a pointed tip.
static float bivioArrow(float3 p) {
    float d2 = min(sdQuad2(p.xy, float2(-0.1, 0.35), float2(0.5, 0.35), float2(0.5, 0.57), float2(-0.1, 0.57)),
                   sdQuad2(p.xy, float2(0.5, 0.35), float2(0.8, 0.46), float2(0.5, 0.57), float2(0.5, 0.46)));
    return extrude(d2, p.z, 0.04) - 0.02;
}

// Agente: a signpost, a pole on a round foot with two arrows pointing in opposite directions.
static float bivio(float3 p, float) {
    float pole = sdSegment(p, float3(0, -0.85, 0), float3(0, 0.8, 0), 0.05);
    float cap = length(p - float3(0, 0.84, 0)) - 0.08;
    float foot = sdCylinder(p - float3(0, -0.88, 0), 0.25, 0.03) - 0.02;
    float right = bivioArrow(p);
    float left = bivioArrow(float3(-p.x, p.y + 0.5, p.z));
    return min(min(pole, cap), min(foot, min(right, left)));
}

ORB_FORMA(bivio)
