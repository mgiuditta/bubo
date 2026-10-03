#include "../OrbShading.h"

// Creativo: a top hat, a tall crown with a ribbon band and a wide flat brim.
static float cilindro(float3 p, float) {
    float crown = sdCylinder(p - float3(0, 0.15, 0), 0.37, 0.38) - 0.03;
    float ribbon = sdCylinder(p - float3(0, -0.18, 0), 0.39, 0.07) - 0.03;
    float brim = sdCylinder(p - float3(0, -0.34, 0), 0.69, 0.03) - 0.04;
    return min(crown, min(ribbon, brim));
}

ORB_FORMA(cilindro)
