#include "../OrbShading.h"

// Viaggi: a square parking sign, a rounded frame around a bold letter P drawn as a stem and a half-round bowl.
static float parcheggio(float3 p, float) {
    float frame = abs(sdRoundBox2(p.xy, float2(0.72, 0.72), 0.15)) - 0.06;
    float stem = udSegment2(p.xy, float2(-0.2, -0.4), float2(-0.2, 0.4));
    float bowl = min(min(udSegment2(p.xy, float2(-0.2, 0.4), float2(0.1, 0.4)), udSegment2(p.xy, float2(-0.2, 0.0), float2(0.1, 0.0))),
                     min(udQuarterArc(p.xy, float2(0.1, 0.2), 0.2, float2(1, 1)), udQuarterArc(p.xy, float2(0.1, 0.2), 0.2, float2(1, -1))));
    float letter = min(stem, bowl) - 0.08;
    return extrude(min(frame, letter), p.z, 0.1) - 0.02;
}

ORB_FORMA(parcheggio)
