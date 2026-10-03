#include "../OrbShading.h"

// Meteo · gelo: three icicles of different lengths hanging from an eave, and two small ones at its ends.
static float ghiacciolo(float3 p, float) {
    float eave = sdRoundBox(p - float3(0, 0.8, 0), float3(0.88, 0.08, 0.14), 0.04);
    float d = sdRoundCone(p, float3(-0.5, 0.75, 0), float3(-0.5, -0.45, 0), 0.14, 0.02);
    d = min(d, sdRoundCone(p, float3(0, 0.75, 0), float3(0, -0.85, 0), 0.14, 0.02));
    d = min(d, sdRoundCone(p, float3(0.5, 0.75, 0), float3(0.5, -0.15, 0), 0.14, 0.02));
    float ends = sdRoundCone(float3(abs(p.x), p.y, p.z), float3(0.8, 0.75, 0), float3(0.8, 0.25, 0), 0.08, 0.02);
    return min(min(eave, d), ends);
}

ORB_FORMA(ghiacciolo)
