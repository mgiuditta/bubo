#include "../OrbShading.h"

// Agente: a toolbox with a latched lid seam and an arched handle.
static float cassetta_attrezzi(float3 p, float) {
    float box = sdRoundBox(p - float3(0, -0.2, 0), float3(0.80, 0.33, 0.30), 0.06);
    float band = sdRoundBox(p - float3(0, 0.0, 0), float3(0.82, 0.04, 0.32), 0.02);
    float3 q = float3(abs(p.x), p.y, p.z);
    float latch = sdRoundBox(q - float3(0.5, 0.0, 0), float3(0.07, 0.10, 0.33), 0.02);
    float arch = min(sdSegment(q, float3(0.25, 0.10, 0), float3(0.25, 0.42, 0), 0.045),
                     sdSegment(q, float3(0.25, 0.42, 0), float3(0, 0.42, 0), 0.045));
    return min(min(box, band), min(latch, arch));
}

ORB_FORMA(cassetta_attrezzi)
