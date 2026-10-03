#include "../OrbShading.h"

// Tempo · cose che si ripetono: a pendulum, a rod from the pivot to a disc with a ring; it swings.
static float pendolo(float3 p, float t) {
    const float2 pivot = float2(0, 0.85);
    float3 q = p;
    q.xy = (p.xy - pivot) * rot(0.45 * sin(t * 2.0)) + pivot;
    float rod = sdSegment(q, float3(0, 0.85, 0), float3(0, -0.4, 0), 0.045);
    float disc = extrude(length(q.xy - float2(0, -0.55)) - 0.28, q.z, 0.07) - 0.04;
    float ring = sdTorusXY(q - float3(0, -0.55, 0.1), 0.18, 0.03);
    float nub = length(q - float3(0, 0.85, 0)) - 0.09;
    return min(min(rod, disc), min(ring, nub));
}

ORB_FORMA(pendolo)
