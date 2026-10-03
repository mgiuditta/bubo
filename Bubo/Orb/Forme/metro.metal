#include "../OrbShading.h"

// Codice · misura: a round tape measure, a ring with its hub, and the tape pulled out along the bottom.
static float metro(float3 p, float) {
    const float2 c = float2(-0.22, 0.18);
    const float R = 0.50;
    float ring = abs(length(p.xy - c) - R) - 0.045;
    float hub = length(p.xy - c) - 0.17;
    float tape = min(udSegment2(p.xy, float2(c.x, c.y - R), float2(0.85, c.y - R)),
                     udSegment2(p.xy, float2(0.85, c.y - R), float2(0.85, c.y - R + 0.20))) - 0.035;
    return extrude(min(min(ring, hub), tape), p.z, 0.04) - 0.03;
}

ORB_FORMA(metro)
