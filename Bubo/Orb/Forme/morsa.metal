#include "../OrbShading.h"

// Agente · compattazione: a bench vice whose moving jaw squeezes in and eases out along the screw.
static float morsa(float3 p, float t) {
    p.x += 0.2;
    float squeeze = 0.12 * (0.5 + 0.5 * sin(t * 1.5));
    float base = sdRoundBox2(p.xy - float2(0, -0.58), float2(0.58, 0.16), 0.05);
    float fixedJaw = sdRoundBox2(p.xy - float2(-0.4, -0.08), float2(0.17, 0.42), 0.04);
    float2 m = p.xy - float2(0.4 - squeeze, -0.08);
    float movingJaw = sdRoundBox2(m, float2(0.17, 0.42), 0.04);
    float screw = udSegment2(p.xy, float2(0.55 - squeeze, -0.2), float2(0.95 - squeeze, -0.2)) - 0.05;
    float handle = udSegment2(p.xy, float2(0.95 - squeeze, -0.55), float2(0.95 - squeeze, 0.15)) - 0.045;
    float jaws = min(min(base, fixedJaw), min(movingJaw, min(screw, handle)));
    float slide = udSegment2(p.xy, float2(-0.2, -0.45), float2(0.4 - squeeze, -0.45)) - 0.05;
    return extrude(min(jaws, slide), p.z, 0.12) - 0.04;
}

ORB_FORMA(morsa)
