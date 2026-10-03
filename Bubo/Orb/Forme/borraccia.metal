#include "../OrbShading.h"

// Salute · idratazione: a water bottle with a label band, a sloped shoulder and a sport cap with its spout.
static float borraccia(float3 p, float) {
    float body = sdCylinder(p - float3(0, -0.25, 0), 0.36, 0.55);
    float band = sdCylinder(p - float3(0, -0.3, 0), 0.38, 0.07);
    float shoulder = sdCappedCone(p - float3(0, 0.45, 0), 0.15, 0.34, 0.16);
    float cap = sdCylinder(p - float3(0, 0.7, 0), 0.19, 0.1);
    float spout = sdCylinder(p - float3(0, 0.9, 0), 0.09, 0.1);
    return min(min(body, band), min(shoulder, min(cap, spout)));
}

ORB_FORMA(borraccia)
