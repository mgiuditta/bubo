#include "../OrbShading.h"

// One crayon standing at x on y = -0.7: a body of half-height h with a paper band and a blunt tip.
static float pastelliOne(float3 p, float x, float h) {
    float3 q = p - float3(x, 0, 0);
    float body = sdCylinder(q - float3(0, -0.7 + h, 0), 0.15, h - 0.02) - 0.02;
    float band = sdCylinder(q - float3(0, -0.7 + h, 0), 0.175, 0.12);
    float tip = sdCappedCone(q - float3(0, -0.7 + 2.0 * h + 0.15, 0), 0.15, 0.17, 0.06);
    return min(body, min(band, tip));
}

// Creativo: three wax crayons side by side, the middle one longest.
static float pastelli(float3 p, float) {
    return min(pastelliOne(p, -0.4, 0.45), min(pastelliOne(p, 0.0, 0.55), pastelliOne(p, 0.4, 0.4)));
}

ORB_FORMA(pastelli)
