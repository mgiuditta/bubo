#include "../OrbShading.h"

// Musica · teoria musicale: a treble clef in relief, a stem with a loop round it, a curl on top and a hook below.
static float chiave_di_violino(float3 p, float) {
    float2 u = p.xy;
    float d = udSegment2(u, float2(0.05, 0.62), float2(0.05, -0.62));
    d = min(d, min(udQuarterArc(u, float2(0.25, 0.62), 0.2, float2(-1, 1)), udQuarterArc(u, float2(0.25, 0.62), 0.2, float2(1, 1))));
    d = min(d, udSegment2(u, float2(0.45, 0.62), float2(0.25, 0.22)));
    d = min(d, abs(length(u - float2(0, -0.1)) - 0.38));
    d = min(d, abs(length(u - float2(0.05, -0.05)) - 0.17));
    d = min(d, min(udQuarterArc(u, float2(-0.15, -0.62), 0.2, float2(1, -1)), udQuarterArc(u, float2(-0.15, -0.62), 0.2, float2(-1, -1))));
    float ball = length(p - float3(-0.35, -0.62, 0)) - 0.09;
    return min(extrude(d - 0.065, p.z, 0.04) - 0.02, ball);
}

ORB_FORMA(chiave_di_violino)
