#include "../OrbShading.h"

// Creativo: a glue tube leaning to the right, a tapering body with a crimped end, a ring and a nozzle cap, and a drop.
static float colla(float3 p, float) {
    float drop = length(p - float3(-0.6, 0.6, 0)) - 0.1;
    float3 q = p;
    q.xy = q.xy * rot(0.45);
    float body = sdCappedCone(q - float3(0, -0.1, 0), 0.55, 0.35, 0.2);
    float crimp = sdRoundBox(q - float3(0, -0.68, 0), float3(0.34, 0.04, 0.1), 0.02);
    float ring = sdCylinder(q - float3(0, 0.46, 0), 0.23, 0.03);
    float cap = sdCappedCone(q - float3(0, 0.64, 0), 0.17, 0.14, 0.07);
    return min(min(body, crimp), min(ring, min(cap, drop)));
}

ORB_FORMA(colla)
