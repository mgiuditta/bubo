#include "../OrbShading.h"

// Codice · rilascio: a git branch: a trunk with two round nodes, and a third node it forks to on the right.
static float ramo(float3 p, float) {
    const float x = -0.32, tube = 0.07, node = 0.17;
    float line = min(udSegment2(p.xy, float2(x, -0.62), float2(x, 0.62)),
                     udQuarterArc(p.xy, float2(x + 0.62, -0.22), 0.62, float2(-1, 1)));
    float d = length(float2(line, p.z)) - tube;
    d = min(d, length(p - float3(x, -0.62, 0)) - node);
    d = min(d, length(p - float3(x, 0.62, 0)) - node);
    return min(d, length(p - float3(x + 0.62, 0.40, 0)) - node);
}

ORB_FORMA(ramo)
