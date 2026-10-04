#include "../OrbShading.h"

// Chat · conversazione: a screwdriver on the slant; it turns on its own axis, so the flat handle opens and narrows.
static float cacciavite(float3 p, float t) {
    p.xy = p.xy * rot(0.6);
    float3 h = p - float3(0, 0.35, 0);
    h.xz = h.xz * rot(t * 2.0);
    float handle = sdRoundBox(h, float3(0.17, 0.3, 0.1), 0.06);
    float ferrule = sdCylinder(p - float3(0, 0.04, 0), 0.09, 0.04);
    float shaft = sdCylinder(p - float3(0, -0.27, 0), 0.045, 0.32);
    float tip = sdCappedCone(p - float3(0, -0.62, 0), 0.07, 0.025, 0.06);
    return min(min(handle, ferrule), min(shaft, tip));
}

ORB_FORMA(cacciavite)
