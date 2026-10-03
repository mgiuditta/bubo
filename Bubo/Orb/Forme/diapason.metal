#include "../OrbShading.h"

// Musica: a tuning fork, a U of two prongs on a handle with a round end; the prongs vibrate.
static float diapason(float3 p, float t) {
    float lean = 0.05 * sin(t * 14.0);
    float u = min(min(udQuarterArc(p.xy, float2(0), 0.2, float2(-1, -1)), udQuarterArc(p.xy, float2(0), 0.2, float2(1, -1))),
                  min(udSegment2(p.xy, float2(-0.2, 0), float2(-0.2 - lean, 0.8)), udSegment2(p.xy, float2(0.2, 0), float2(0.2 + lean, 0.8))));
    float fork = extrude(u - 0.07, p.z, 0.04) - 0.03;
    float handle = min(sdSegment(p, float3(0, -0.2, 0), float3(0, -0.68, 0), 0.08), length(p - float3(0, -0.78, 0)) - 0.11);
    return min(fork, handle);
}

ORB_FORMA(diapason)
