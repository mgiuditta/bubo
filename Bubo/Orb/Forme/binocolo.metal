#include "../OrbShading.h"

// Ricerca: binoculars, two tapering tubes joined by a bridge, with rims at the lenses and the eyepieces.
static float binocolo(float3 p, float) {
    float3 q = float3(abs(p.x), p.y, p.z);
    float tube = sdCappedCone(q - float3(0.32, 0, 0), 0.55, 0.28, 0.20) - 0.02;
    float objective = sdCylinder(q - float3(0.32, -0.56, 0), 0.31, 0.05) - 0.02;
    float eyepiece = sdCylinder(q - float3(0.32, 0.58, 0), 0.22, 0.04) - 0.02;
    float bridge = sdRoundBox(p - float3(0, 0.05, 0), float3(0.22, 0.09, 0.10), 0.05);
    return min(min(tube, bridge), min(objective, eyepiece));
}

ORB_FORMA(binocolo)
