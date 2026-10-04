#include "../OrbShading.h"

// Salute · proteine: a whole egg, upright, rounder at the bottom.
static float uovo(float3 p, float) {
    return sdRoundCone(p, float3(0, -0.25, 0), float3(0, 0.30, 0), 0.60, 0.42);
}

ORB_FORMA(uovo)
