#include "../OrbShading.h"

// Creativo: a lipstick, its slanted bullet rising from the case, and the cap standing beside it.
static float rossetto(float3 p, float) {
    float base = sdCylinder(p - float3(-0.35, -0.5, 0), 0.2, 0.3);
    float band = sdCylinder(p - float3(-0.35, -0.05, 0), 0.17, 0.15);
    float bullet = sdRoundCone(p, float3(-0.35, 0.1, 0), float3(-0.27, 0.6, 0), 0.14, 0.08);
    float cap = sdCylinder(p - float3(0.45, -0.32, 0), 0.22, 0.48);
    return min(min(base, band), min(bullet, cap));
}

ORB_FORMA(rossetto)
