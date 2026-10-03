#include "../OrbShading.h"

// Musica: a microphone with a round head on a short stand.
static float microfono(float3 p, float) {
    float head = length(p - float3(0, 0.40, 0)) - 0.30;
    float band = sdCylinder(p - float3(0, 0.40, 0), 0.31, 0.03);
    float body = sdCappedCone(p - float3(0, -0.15, 0), 0.35, 0.09, 0.20);
    float stand = sdSegment(p, float3(0, -0.50, 0), float3(0, -0.80, 0), 0.05);
    float base = sdCylinder(p - float3(0, -0.85, 0), 0.30, 0.04);
    return min(min(head, band), min(body, min(stand, base)));
}

ORB_FORMA(microfono)
