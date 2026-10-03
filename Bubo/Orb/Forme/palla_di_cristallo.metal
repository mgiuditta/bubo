#include "../OrbShading.h"

// Ricerca: a crystal ball on a low flared stand.
static float palla_di_cristallo(float3 p, float) {
    float ball = length(p - float3(0, 0.18, 0)) - 0.62;
    float stand = sdCappedCone(p - float3(0, -0.62, 0), 0.18, 0.5, 0.3);
    float collar = sdCylinder(p - float3(0, -0.45, 0), 0.34, 0.04);
    return min(ball, min(stand, collar));
}

ORB_FORMA(palla_di_cristallo)
