#include "../OrbShading.h"

// Creativo: a spray can with its shoulder, cap, button and nozzle.
static float bomboletta(float3 p, float) {
    p.y += 0.11;
    float body = sdCylinder(p - float3(0, -0.2, 0), 0.28, 0.45);
    float shoulder = sdCappedCone(p - float3(0, 0.35, 0), 0.10, 0.28, 0.17);
    float cap = sdCylinder(p - float3(0, 0.60, 0), 0.17, 0.15);
    float button = sdCylinder(p - float3(0, 0.80, 0), 0.08, 0.05);
    float nozzle = sdSegment(p, float3(0, 0.82, 0), float3(0.26, 0.82, 0), 0.04);
    return min(min(body, shoulder), min(cap, min(button, nozzle)));
}

ORB_FORMA(bomboletta)
