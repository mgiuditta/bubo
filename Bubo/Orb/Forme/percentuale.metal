#include "../OrbShading.h"

// Finanza · tassi: the percent sign, two rings and a slash.
static float percentuale(float3 p, float) {
    float d = udSegment2(p.xy, float2(-0.55, -0.72), float2(0.55, 0.72)) - 0.06;
    d = min(d, abs(length(p.xy - float2(-0.42, 0.45)) - 0.20) - 0.055);
    d = min(d, abs(length(p.xy - float2(0.42, -0.45)) - 0.20) - 0.055);
    return extrude(d, p.z, 0.04) - 0.03;
}

ORB_FORMA(percentuale)
