#include "../OrbShading.h"

// Codice · scrittura: long-nose pliers, closed, jaws up and the handles spread.
static float pinza(float3 p, float) {
    float3 q = float3(abs(p.x), p.y - 0.05, p.z);      // the two halves are mirror images
    float jaw = sdRoundCone(q, float3(0.07, 0.0, 0), float3(0.02, 0.82, 0), 0.10, 0.03);
    float handle = sdSegment(q, float3(0.05, -0.02, 0), float3(0.40, -0.86, 0), 0.10);
    float pivot = length(q - float3(0, 0, 0.06)) - 0.13;
    return min(min(jaw, handle), pivot);
}

ORB_FORMA(pinza)
