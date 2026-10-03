#include "../OrbShading.h"

// Codice: a star cookie cutter, a thin wall in the shape of a star with a wider rim at the back.
static float formina(float3 p, float) {
    float star = sdStar5(p.xy, 0.82, 0.5);
    float wall = extrude(abs(star) - 0.055, p.z, 0.2) - 0.03;
    float rim = extrude(abs(star) - 0.11, p.z + 0.18, 0.03) - 0.02;
    return min(wall, rim);
}

ORB_FORMA(formina)
