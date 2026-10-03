#include "../OrbShading.h"

// Salute: a lotion bottle with a pump, a rounded body, a neck, a stem and a pump head with its spout.
static float crema(float3 p, float) {
    float body = sdRoundBox(p - float3(0, -0.25, 0), float3(0.4, 0.5, 0.28), 0.2);
    float neck = sdCylinder(p - float3(0, 0.32, 0), 0.13, 0.08);
    float stem = sdCylinder(p - float3(0, 0.5, 0), 0.06, 0.12);
    float head = sdRoundBox(p - float3(0.12, 0.66, 0), float3(0.26, 0.06, 0.07), 0.04);
    return min(min(body, neck), min(stem, head));
}

ORB_FORMA(crema)
