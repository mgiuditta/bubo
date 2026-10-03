#include "../OrbShading.h"

// Chat: a classical column, a plinth, a round shaft and a capital with its flared neck and slab.
static float colonna(float3 p, float) {
    float shaft = sdCylinder(p, 0.22, 0.5);
    float rings = min(sdCylinder(p - float3(0, -0.5, 0), 0.27, 0.04), sdCylinder(p - float3(0, 0.46, 0), 0.27, 0.03));
    float plinth = sdRoundBox(p - float3(0, -0.62, 0), float3(0.38, 0.1, 0.38), 0.03);
    float neck = sdCappedCone(p - float3(0, 0.54, 0), 0.08, 0.22, 0.34);
    float slab = sdRoundBox(p - float3(0, 0.7, 0), float3(0.42, 0.09, 0.42), 0.03);
    return min(min(shaft, rings), min(plinth, min(neck, slab)));
}

ORB_FORMA(colonna)
