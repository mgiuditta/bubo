#include "../OrbShading.h"

// Musica · tradizioni dal mondo: a bagpipe, the round bag with a blowpipe, three drones and a chanter.
static float cornamusa(float3 p, float) {
    float bag = length(p - float3(-0.02, -0.12, 0)) - 0.44;
    float blow = sdSegment(p, float3(-0.3, 0.2, 0), float3(-0.62, 0.62, 0), 0.06);
    float tip = length(p - float3(-0.64, 0.64, 0)) - 0.08;
    float drones = min(sdSegment(p, float3(-0.12, 0.3, 0), float3(-0.2, 0.92, 0), 0.055),
                       min(sdSegment(p, float3(0.0, 0.34, 0), float3(0.08, 0.98, 0), 0.055),
                           sdSegment(p, float3(0.14, 0.3, 0), float3(0.34, 0.9, 0), 0.055)));
    float bells = min(length(p - float3(-0.2, 0.94, 0)) - 0.09, min(length(p - float3(0.08, 1.0, 0)) - 0.09, length(p - float3(0.35, 0.92, 0)) - 0.09));
    float chanter = sdSegment(p, float3(0.2, -0.38, 0), float3(0.5, -0.9, 0), 0.06);
    float flare = length(p - float3(0.52, -0.92, 0)) - 0.1;
    return min(min(min(bag, blow), min(tip, drones)), min(min(bells, chanter), flare));
}

ORB_FORMA(cornamusa)
