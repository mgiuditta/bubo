#include "../OrbShading.h"

// Ricerca · dato preciso: an archery target with two rings and a boss, an arrow stuck in its centre.
static float bersaglio(float3 p, float) {
    float disc = extrude(length(p.xy) - 0.85, p.z, 0.05) - 0.02;
    float rings = min(sdTorusXY(p - float3(0, 0, 0.07), 0.62, 0.045), sdTorusXY(p - float3(0, 0, 0.07), 0.36, 0.045));
    float boss = length(p - float3(0, 0, 0.07)) - 0.1;
    float shaft = sdSegment(p, float3(0, 0, 0.1), float3(0.7, 0.7, 0.62), 0.04);
    float fletch = min(sdSegment(p, float3(0.6, 0.6, 0.54), float3(0.5, 0.76, 0.68), 0.03),
                       sdSegment(p, float3(0.6, 0.6, 0.54), float3(0.76, 0.5, 0.68), 0.03));
    return min(min(disc, rings), min(boss, min(shaft, fletch)));
}

ORB_FORMA(bersaglio)
