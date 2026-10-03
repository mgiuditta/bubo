#include "../OrbShading.h"

// Chat: a four-leaf clover, four hearts meeting at the middle, with a curved stem.
static float quadrifoglio(float3 p, float) {
    float2 q = p.xy;
    float d = udSegment2(q, float2(0, -0.10), float2(0.04, -0.50)) - 0.045;
    d = min(d, udSegment2(q, float2(0.04, -0.50), float2(0.20, -0.85)) - 0.045);
    float2 r = q * rot(M_PI_F * 0.25);
    for (int k = 0; k < 4; k++) {
        float2 leaf = r * rot(float(k) * M_PI_F * 0.5);
        d = min(d, sdHeart2(leaf / 0.55) * 0.55);
    }
    return extrude(d, p.z, 0.04) - 0.02;
}

ORB_FORMA(quadrifoglio)
