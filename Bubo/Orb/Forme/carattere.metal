#include "../OrbShading.h"

// Creativo: a serif capital A: a thin left stroke, a thick right one, a crossbar and serifs.
static float carattere(float3 p, float) {
    float2 q = p.xy;
    float d = udSegment2(q, float2(0, 0.75), float2(-0.45, -0.70)) - 0.05;
    d = min(d, udSegment2(q, float2(0, 0.75), float2(0.45, -0.70)) - 0.09);
    d = min(d, udSegment2(q, float2(-0.22, -0.20), float2(0.22, -0.20)) - 0.04);
    d = min(d, udSegment2(q, float2(-0.62, -0.72), float2(-0.30, -0.72)) - 0.035);
    d = min(d, udSegment2(q, float2(0.30, -0.72), float2(0.62, -0.72)) - 0.035);
    d = min(d, udSegment2(q, float2(-0.10, 0.78), float2(0.12, 0.78)) - 0.04);
    return extrude(d, p.z, 0.05) - 0.02;
}

ORB_FORMA(carattere)
