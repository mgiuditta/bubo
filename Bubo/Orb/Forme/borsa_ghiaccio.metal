#include "../OrbShading.h"

// Salute · corpo: an ice pack, a flat bag with seams, a short neck and a screw cap.
static float borsa_ghiaccio(float3 p, float) {
    p.y += 0.11;
    float bag = sdRoundBox(p - float3(0, -0.1, 0), float3(0.42, 0.5, 0.14), 0.12);
    float neck = sdCylinder(p - float3(0, 0.5, 0), 0.13, 0.1);
    float cap = sdCylinder(p - float3(0, 0.72, 0), 0.18, 0.1);
    float seams = min(sdRoundBox(p - float3(0, 0.0, 0.14), float3(0.28, 0.02, 0.02), 0.01),
                      sdRoundBox(p - float3(0, -0.28, 0.14), float3(0.28, 0.02, 0.02), 0.01));
    return min(min(bag, neck), min(cap, seams));
}

ORB_FORMA(borsa_ghiaccio)
