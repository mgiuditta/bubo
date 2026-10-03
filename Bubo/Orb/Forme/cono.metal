#include "../OrbShading.h"

// Agente: a traffic cone with two bands, on a square base.
static float cono(float3 p, float) {
    float cone = sdCappedCone(p - float3(0, -0.04, 0), 0.62, 0.5, 0.12);
    float b1 = sdCappedCone(p - float3(0, -0.2, 0), 0.06, 0.418, 0.381);
    float b2 = sdCappedCone(p - float3(0, 0.2, 0), 0.06, 0.295, 0.258);
    float base = sdRoundBox(p - float3(0, -0.7, 0), float3(0.72, 0.08, 0.7), 0.03);
    return min(min(cone, base), min(b1, b2));
}

ORB_FORMA(cono)
