#include "../OrbShading.h"

// Creativo: a table lamp, a truncated-cone shade over a bulb, on a thin stem and a round base.
static float lampada(float3 p, float) {
    float shade = sdCappedCone(p - float3(0, 0.42, 0), 0.28, 0.52, 0.26);
    float stem = sdCylinder(p - float3(0, -0.2, 0), 0.05, 0.5);
    float base = sdCylinder(p - float3(0, -0.72, 0), 0.36, 0.03) - 0.04;
    float bulb = length(p - float3(0, 0.08, 0)) - 0.11;
    return min(min(shade, stem), min(base, bulb));
}

ORB_FORMA(lampada)
